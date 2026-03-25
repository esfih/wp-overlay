#!/usr/bin/env bash
# Git-Bash-native helper for local WordPress Docker operations.
# Usage: ./scripts/wp.sh <command> [args...]
#
# Commands:
#   wp <args>       Run a WP-CLI command inside the wordpress7 container
#   eval "<php>"    Execute PHP with full WordPress bootstrap (wpdb initialized)
#   db "<sql>"      Run a SQL query against the db7 MySQL container
#   log [N]         Tail the WordPress debug log (default: 80 lines)
#   php <file>      Copy a local PHP file into the container and run it via wp eval-file
#   shell           Open an interactive bash shell inside the wordpress7 container
#
# All patterns follow foundation/wp/docs/WP-LOCAL-OPS.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Resolve runtime config ────────────────────────────────────────────────────
WP_SERVICE="wordpress7"
DB_SERVICE="db7"
DB_NAME="${DB7_NAME:-wordpress7}"
DB_USER="${DB7_USER:-wp_user7}"
DB_PASS="${DB7_PASSWORD:-wp_pass_dev7}"
LOG_PATH="$REPO_ROOT/logs/wp7/debug.log"

# Load overrides from .env if present
if [[ -f "$REPO_ROOT/.env" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      DB7_NAME)     DB_NAME="$value" ;;
      DB7_USER)     DB_USER="$value" ;;
      DB7_PASSWORD) DB_PASS="$value" ;;
    esac
  done < <(grep -E '^(DB7_NAME|DB7_USER|DB7_PASSWORD)=' "$REPO_ROOT/.env" || true)
fi

# ── Guards ────────────────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker CLI not found." >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  cat <<'USAGE'
Usage: ./scripts/wp.sh <command> [args...]

Commands:
  wp <args>       Run WP-CLI inside the wordpress7 container
  eval "<php>"    Run PHP with full WordPress bootstrap (wpdb initialized)
  db "<sql>"      Run a SQL query against the db7 MySQL container
  log [N]         Tail the debug log (default: 80 lines; host path: logs/wp7/debug.log)
  php <file>      Copy local PHP file to container and run via wp eval-file
  shell           Open interactive bash shell inside wordpress7
USAGE
  exit 0
fi

COMMAND="$1"
shift

# ── MSYS_NO_PATHCONV prevents Git Bash from mangling Linux absolute paths ─────
export MSYS_NO_PATHCONV=1

case "$COMMAND" in

  wp)
    if [[ $# -eq 0 ]]; then
      echo "Usage: ./scripts/wp.sh wp <wp-cli-args>" >&2
      exit 1
    fi
    docker exec -i "$WP_SERVICE" wp "$@" --allow-root
    ;;

  eval)
    if [[ $# -eq 0 ]]; then
      echo "Usage: ./scripts/wp.sh eval \"<php code>\"" >&2
      exit 1
    fi
    docker exec -i "$WP_SERVICE" wp eval "$1" --allow-root
    ;;

  db)
    if [[ $# -eq 0 ]]; then
      echo "Usage: ./scripts/wp.sh db \"<sql query>\"" >&2
      exit 1
    fi
    docker exec -i "$DB_SERVICE" mysql \
      -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
      -e "$1"
    ;;

  log)
    LINES="${1:-80}"
    if [[ ! -f "$LOG_PATH" ]]; then
      echo "Debug log not found: $LOG_PATH"
      echo "Trigger any PHP action inside WordPress to create it (WP_DEBUG_LOG is already on)."
      exit 0
    fi
    tail -n "$LINES" "$LOG_PATH"
    ;;

  php)
    if [[ $# -eq 0 ]]; then
      echo "Usage: ./scripts/wp.sh php <local-php-file>" >&2
      exit 1
    fi
    LOCAL_FILE="$1"
    if [[ ! -f "$LOCAL_FILE" ]]; then
      echo "File not found: $LOCAL_FILE" >&2
      exit 1
    fi
    BASENAME="$(basename "$LOCAL_FILE")"
    CONTAINER_PATH="/tmp/$BASENAME"
    docker cp "$LOCAL_FILE" "$WP_SERVICE:$CONTAINER_PATH"
    docker exec -i "$WP_SERVICE" wp eval-file "$CONTAINER_PATH" --allow-root
    ;;

  shell)
    docker exec -it "$WP_SERVICE" bash
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Run ./scripts/wp.sh with no arguments to see usage." >&2
    exit 1
    ;;

esac
