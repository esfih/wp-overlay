---
title: WordPress Local Operations
type: foundation-guide
status: active
authority: primary
intent-scope: implementation,debugging,maintenance
phase: active
last-reviewed: 2026-03-23
ide-context-token-estimate: 1600
token-estimate-method: approx-chars-div-4
related-files:
  - ../../../DEVOPS-TECH-STACK.md
  - ../../../docker-compose.yml
  - ../../../scripts/wp.sh
  - ../../../dev.ps1
---

# WordPress Local Operations

## Purpose

This file is the canonical reference for interacting with the local WordPress Docker instance.

Read this before issuing any `docker`, `wp`, `mysql`, or REST API command against the local WordPress runtime.

Failure to follow these patterns is the root cause of common AI errors such as:
- "wpdb isn't initialized in the command line"
- "mysql command not found in Git Bash"
- broken WP-CLI invocations
- debug log not found

---

## Runtime Summary

| Resource | Value |
|---|---|
| WordPress container | `wordpress7` |
| DB container | `db7` |
| WordPress URL | `http://localhost:8090` |
| wp-admin URL | `http://localhost:8090/wp-admin` |
| REST API base | `http://localhost:8090/wp-json/wp/v2/` |
| phpMyAdmin URL | `http://localhost:8091` |
| Debug log (host) | `./logs/wp7/debug.log` |
| Debug log (container) | `/var/www/html/wp-content/logs/debug.log` |
| Plugin mounts | `./webmasteros` and `./private-plugins/wmos-control-plane` |
| DB name | `wordpress7` (override via `DB7_NAME` in `.env`) |
| DB user | `wp_user7` (override via `DB7_USER` in `.env`) |
| DB password | `wp_pass_dev7` (override via `DB7_PASSWORD` in `.env`) |

`WP_DEBUG`, `WP_DEBUG_LOG`, and `WP_DEBUG_DISPLAY` are all `1` in `docker-compose.yml` — debug logging is always active in the local lane.

---

## Quick-Access Script

**Always prefer `scripts/wp.sh` over raw Docker commands.**

```bash
# Run any WP-CLI command
./scripts/wp.sh wp plugin list

# Execute PHP with full WordPress bootstrapped (wpdb is initialized)
./scripts/wp.sh eval 'global $wpdb; var_dump($wpdb->get_results("SELECT ID, post_title FROM wp_posts LIMIT 5"));'

# Run an inline SQL query against the DB container
./scripts/wp.sh db "SELECT option_name, option_value FROM wmos7_options WHERE option_name LIKE 'siteurl' LIMIT 1;"

# Tail the debug log (last 50 lines; omit N for 80)
./scripts/wp.sh log 50

# Execute a local PHP file inside the container (safe pattern for complex scripts)
./scripts/wp.sh php /path/to/local-script.php

# Open a bash shell inside the WordPress container
./scripts/wp.sh shell
```

---

## WP-CLI — Canonical Pattern

WP-CLI is installed at `/usr/local/bin/wp` inside the `wordpress7` container.

**Never run `wp` commands on the host.** There is no host WP-CLI installation. Git Bash does not have access to the WordPress filesystem or database connection.

```bash
# Correct:
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp plugin list --allow-root

# Wrong — will fail or do nothing useful:
wp plugin list
```

Always append `--allow-root` because the container runs as root.

Always set `MSYS_NO_PATHCONV=1` before `docker exec` commands that pass Linux absolute paths (Windows path conversion will corrupt them).

Common WP-CLI commands:

```bash
# List plugins
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp plugin list --allow-root

# Activate a plugin
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp plugin activate webmasteros --allow-root

# Check option value
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp option get siteurl --allow-root

# Flush rewrite rules
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp rewrite flush --allow-root

# Run a cron event manually
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp cron event run --due-now --allow-root
```

---

## PHP with WordPress Bootstrap — `wp eval` Pattern

**Use `wp eval` to run PHP that needs WordPress initialized (e.g., `$wpdb`, hooks, functions).**

Do NOT write a standalone PHP script and run it with `php` directly if it calls WordPress functions. `php script.php` from CLI will not bootstrap WordPress and `$wpdb` will be uninitialized.

```bash
# Query the database with wpdb (correct):
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp eval \
  'global $wpdb; $rows = $wpdb->get_results("SELECT ID, post_title FROM {$wpdb->posts} LIMIT 5"); var_dump($rows);' \
  --allow-root

# Check a WordPress constant or function:
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp eval 'echo get_option("siteurl");' --allow-root
```

For longer PHP scripts, use the `php <file>` command in `scripts/wp.sh` — it copies the file into the container first and then runs it inside the correct WordPress environment using `wp eval-file`.

---

## Database Queries — Canonical Pattern

MySQL is installed inside the `db7` container as `mariadb-client`. There is no `mysql` command available on the Git Bash host.

```bash
# Run a SQL query:
MSYS_NO_PATHCONV=1 docker exec db7 mysql \
  -u wp_user7 -pwp_pass_dev7 wordpress7 \
  -e "SELECT option_name, option_value FROM wmos7_options WHERE option_name = 'siteurl';"

# Dump a table:
MSYS_NO_PATHCONV=1 docker exec db7 mysqldump \
  -u wp_user7 -pwp_pass_dev7 wordpress7 wmos7_options > /tmp/options-dump.sql
```

Alternative: open phpMyAdmin at `http://localhost:8091` for visual DB inspection.

Alternative: use `./scripts/wp.sh db "<SQL>"` to avoid remembering credentials.

---

## PHP Script Execution — Safe Pattern

When a task requires a longer PHP script that cannot fit in a single `wp eval` inline string:

1. Write the script to a local temp file.
2. Use `docker cp` to copy it into the container.
3. Execute it with `docker exec`.

**Never inline heredocs directly into `docker exec` — stdin piping to `docker exec` is unreliable in Git Bash.**

```bash
# 1. Write script locally
cat > /tmp/wmos-inspect.php << 'EOF'
<?php
// This runs inside the container via wp eval-file — WordPress is bootstrapped
global $wpdb;
$count = $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts}");
echo "Post count: $count\n";
EOF

# 2. Copy into container
MSYS_NO_PATHCONV=1 docker cp /tmp/wmos-inspect.php wordpress7:/tmp/wmos-inspect.php

# 3. Execute with WP bootstrap
MSYS_NO_PATHCONV=1 docker exec wordpress7 wp eval-file /tmp/wmos-inspect.php --allow-root
```

Or simply use `./scripts/wp.sh php /tmp/wmos-inspect.php` which handles steps 2 and 3.

---

## Debug Log

`WP_DEBUG_LOG` is always on in the local lane. Logs are written to `/var/www/html/wp-content/logs/debug.log` inside the container, which is bind-mounted to `./logs/wp7/debug.log` on the host.

```bash
# Tail from host (no Docker needed):
tail -f ./logs/wp7/debug.log

# Or use the script:
./scripts/wp.sh log 50

# Or PowerShell tail equivalent:
Get-Content logs\wp7\debug.log -Wait -Tail 50
```

If the log file does not exist yet, trigger any PHP action inside WordPress and it will be created automatically.

---

## REST API

The local WordPress REST API is available at `http://localhost:8090/wp-json/`.

```bash
# Check site health:
curl -s http://localhost:8090/wp-json/ | python -m json.tool | head -30

# Authenticated request (use Application Password):
curl -s -u "admin:app-password-here" http://localhost:8090/wp-json/wp/v2/plugins
```

All standard REST namespace prefixes (`/wp/v2/`, `/wmos/v1/`, etc.) are available because `WP_DEBUG` enables detailed error output.

---

## Common Failure Modes and Fixes

| Error | Cause | Fix |
|---|---|---|
| `wpdb isn't initialized` | Running PHP with `php script.php` directly | Use `wp eval` or `wp eval-file` |
| `mysql: command not found` | No mysql on Git Bash host | Use `docker exec db7 mysql ...` |
| WP-CLI not found | Running `wp` on host | Use `docker exec wordpress7 wp ... --allow-root` |
| Path mangled (`C:/...` in container) | MSYS path conversion | Set `MSYS_NO_PATHCONV=1` before `docker exec` |
| Debug log empty or missing | Wrong file path | Log is at `./logs/wp7/debug.log` on host |
| Heredoc piped to docker exec fails | Git Bash stdin piping unreliable | Write temp file → `docker cp` → `docker exec` |

---

## App-Local Overrides

Container names and DB credentials are defined in `docker-compose.yml` and can be overridden in `.env`.

When working in this repository, the concrete values are:

- WordPress service: `wordpress7`
- DB service: `db7`
- Ports: WP `8090`, phpMyAdmin `8091`
- DB env vars: `DB7_NAME`, `DB7_USER`, `DB7_PASSWORD`

See `DEVOPS-TECH-STACK.md` for the full local baseline summary.
