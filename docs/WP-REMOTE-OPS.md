---
title: WordPress Remote Operations
type: foundation-guide
status: active
authority: primary
intent-scope: debugging,maintenance,deployment
phase: active
last-reviewed: 2026-04-05
ide-context-token-estimate: 1800
token-estimate-method: approx-chars-div-4
related-files:
  - WP-LOCAL-OPS.md
  - ../scripts/wp-remote.sh
---

# WordPress Remote Operations

## Purpose

This file is the canonical reference for interacting with a **deployed / live** WordPress instance over SSH.

Read this before issuing any SSH, SCP, or remote WP-CLI command against a production or staging server.

It mirrors `WP-LOCAL-OPS.md` in intent, but targets the remote lane instead of the local Docker lane.

---

## Connection Variables

Every app repo that uses this foundation must define these in its own canonical reference
(e.g. `specs/GITHUB-AUTH-REFERENCE.md` → "SSH Connection Reference"):

| Variable | Meaning | Example |
|---|---|---|
| `REMOTE_USER` | SSH login username | `efttsqrtff` |
| `REMOTE_HOST` | Server IP or hostname | `209.16.158.249` |
| `REMOTE_PORT` | SSH port (often non-standard on shared hosting) | `5022` |
| `REMOTE_KEY` | Path to private key on dev machine | `~/.ssh/my_project_key` |
| `REMOTE_WPATH` | Absolute path to WordPress root on server | `/home/user/site.example.com` |

> On mutualized / shared hosting the SSH port is almost never 22.
> Check the hosting panel (cPanel / N0C) for the correct value.

---

## Recommended Wrapper Script

Every project should maintain a thin wrapper `scripts/wp-remote.sh` that reads the variables
above and delegates to SSH + WP-CLI. A canonical minimal implementation:

```bash
#!/usr/bin/env bash
# scripts/wp-remote.sh — remote WP-CLI runner
set -euo pipefail

REMOTE_USER="${REMOTE_USER:-<account-user>}"
REMOTE_HOST="${REMOTE_HOST:-<server-ip>}"
REMOTE_PORT="${REMOTE_PORT:-5022}"
REMOTE_WPATH="${REMOTE_WPATH:-/home/<account-user>/<site-dir>}"
REMOTE_KEY="${REMOTE_KEY:-$HOME/.ssh/<project-key>}"

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <wp-cli args...>"
  exit 1
fi

CMD="wp --path=${REMOTE_WPATH} --allow-root"
for arg in "$@"; do
  CMD+=" $(printf '%q' "$arg")"
done

ssh -i "$REMOTE_KEY" -p "$REMOTE_PORT" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    "${REMOTE_USER}@${REMOTE_HOST}" "$CMD"
```

Override any variable with an environment prefix:
```bash
REMOTE_HOST=staging.example.com ./scripts/wp-remote.sh plugin list
```

---

## Test Connection

Before any diagnostic or deployment action, verify SSH access:

```bash
ssh -i ~/.ssh/<project-key> -p <port> <user>@<host> "echo connected"
```

Expected output: `connected`

Failure modes:
- `Permission denied (publickey)` — key not authorized on server; add public key via hosting panel
- `Connection refused` / `Connection timed out` — wrong port or firewall; verify port in hosting panel
- `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` — server re-keyed; run `ssh-keygen -R "[<host>]:<port>"` then retry

---

## Remote WP-CLI — Canonical Pattern

All remote WP-CLI operations use the wrapper:

```bash
./scripts/wp-remote.sh <wp-cli-args>
```

Common diagnostic commands:

```bash
# List all plugins with status and version
./scripts/wp-remote.sh plugin list

# Check a specific plugin's installed version and status
./scripts/wp-remote.sh plugin get ecomcine --fields=name,version,status

# Read a WordPress option
./scripts/wp-remote.sh option get siteurl

# Check which PHP version WordPress is running on
./scripts/wp-remote.sh eval 'echo phpversion();'

# List active theme
./scripts/wp-remote.sh theme list --status=active

# Flush rewrite rules
./scripts/wp-remote.sh rewrite flush

# Force WordPress to re-check for plugin updates
./scripts/wp-remote.sh transient delete update_plugins
./scripts/wp-remote.sh transient delete <plugin-slug>_update_server_info

# Run a cron event manually
./scripts/wp-remote.sh cron event run wp_update_plugins

# Check update status for a specific plugin
./scripts/wp-remote.sh plugin update <plugin-slug> --dry-run
```

For inline PHP with WordPress context:
```bash
./scripts/wp-remote.sh eval 'echo get_option("active_plugins")[0];'
```

---

## Debug Log

WordPress debug logging (`WP_DEBUG_LOG`) writes to `wp-content/debug.log` (or a custom path
set in `wp-config.php`).

Read the last 50 lines:
```bash
ssh -i ~/.ssh/<project-key> -p <port> <user>@<host> \
  "tail -n 50 <wp-root>/wp-content/debug.log"
```

Stream log live (useful during a test action):
```bash
ssh -i ~/.ssh/<project-key> -p <port> <user>@<host> \
  "tail -f <wp-root>/wp-content/debug.log"
```

If debug.log is empty or missing, verify `wp-config.php` contains:
```php
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_LOG', true );
define( 'WP_DEBUG_DISPLAY', false );
```

Check via remote WP-CLI:
```bash
./scripts/wp-remote.sh eval "echo WP_DEBUG_LOG ? 'on' : 'off';"
```

---

## Filesystem Diagnostics

Check plugin directory ownership (critical for auto-update compatibility):
```bash
ssh -i ~/.ssh/<project-key> -p <port> <user>@<host> \
  "stat <wp-root>/wp-content/plugins/<plugin-slug>"
```

List plugins directory:
```bash
ssh -i ~/.ssh/<project-key> -p <port> <user>@<host> \
  "ls -la <wp-root>/wp-content/plugins/"
```

Identify the PHP process user (needed for ownership fix):
```bash
ssh -i ~/.ssh/<project-key> -p <port> <user>@<host> \
  "ps aux | grep php | head -3"
```

Fix plugin directory ownership for auto-update compatibility:
```bash
# Generic shared hosting (PHP runs as www-data):
ssh -i ~/.ssh/<project-key> -p <port> <user>@<host> \
  "chown -R www-data:www-data <wp-root>/wp-content/plugins/<plugin-slug>"

# N0C / cPanel mutualized hosting (PHP runs as the account user):
ssh -i ~/.ssh/<project-key> -p <port> <user>@<host> \
  "chown -R <account-user> <wp-root>/wp-content/plugins/<plugin-slug>"
```

> See `WP-LOCAL-OPS.md` → "WordPress Auto-Update — Ownership and `clear_destination`"
> for the full explanation of why ownership matters for auto-update.

---

## Deploy a Plugin Release via WP-CLI

Install (or force-upgrade) a specific GitHub release zip directly from the server:

```bash
./scripts/wp-remote.sh plugin install \
  https://github.com/<owner>/<repo>/releases/download/v<version>/<plugin-slug>-<version>.zip \
  --force --activate
```

Verify the installation succeeded:
```bash
./scripts/wp-remote.sh plugin get <plugin-slug> --fields=name,version,status
```

This uses `install()` path (`clear_destination: false`) — it works regardless of file ownership.
Use this as the reliable deployment path when auto-update is blocked by an ownership issue.

---

## Copy a File to the Server (SCP)

```bash
scp -i ~/.ssh/<project-key> -P <port> \
  <local-file> \
  <user>@<host>:<remote-path>
```

Note: SCP uses uppercase `-P` for port (unlike SSH which uses lowercase `-p`).

---

## Common Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `wp: command not found` | WP-CLI not installed on server | Install WP-CLI or use `php wp-cli.phar` path |
| `Error: This does not seem to be a WordPress installation` | Wrong `--path` | Verify `REMOTE_WPATH` points to WP root (contains `wp-config.php`) |
| `Warning: Could not remove the old plugin.` | Plugin dir owned by wrong user | Fix ownership with `chown`; see ownership section above |
| `The package could not be installed.` | Auto-update path; same ownership issue OR no zip on GitHub release | Fix ownership AND verify zip is attached to GitHub release |
| `ssh: connect to host ... port ...: Connection refused` | Wrong port | Check hosting panel for SSH port |
| `Permission denied (publickey)` | Key not authorized | Add public key via hosting panel → SSH access |

