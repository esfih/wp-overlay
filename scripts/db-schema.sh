#!/usr/bin/env bash
# Inspect the live WordPress DB schema inside the local Docker runtime.
# Use this before designing new storage to avoid duplicate tables, missing indexes,
# or blob abuse. Answers the schema design gate questions defined in
# specs/IMPLEMENTATION-RULES.md — New Data Schema Design Gate.
#
# Usage:
#   ./scripts/db-schema.sh tables               List all tables in the WP database
#   ./scripts/db-schema.sh describe <table>     Full column/type/key definition
#   ./scripts/db-schema.sh sample <table> [N]   N sample rows (default: 5)
#   ./scripts/db-schema.sh indexes <table>      Show all indexes on a table
#   ./scripts/db-schema.sh search <pattern>     Find tables matching a name pattern
#
# Requires the local WordPress Docker stack to be running (docker compose up).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DB_SERVICE="db7"
DB_NAME="${DB7_NAME:-wordpress7}"
DB_USER="${DB7_USER:-wp_user7}"
DB_PASS="${DB7_PASSWORD:-wp_pass_dev7}"

# Load .env overrides
if [[ -f "$REPO_ROOT/.env" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      DB7_NAME)     DB_NAME="$value" ;;
      DB7_USER)     DB_USER="$value" ;;
      DB7_PASSWORD) DB_PASS="$value" ;;
    esac
  done < <(grep -E '^(DB7_NAME|DB7_USER|DB7_PASSWORD)=' "$REPO_ROOT/.env" || true)
fi

export MSYS_NO_PATHCONV=1

_db_query() {
  docker exec -i "$DB_SERVICE" mysql \
    -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    --silent \
    -e "$1"
}

_require_table() {
  if [[ -z "${1:-}" ]]; then
    echo "Error: table name required." >&2
    exit 1
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker CLI not found." >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  cat <<'USAGE'
Usage: ./scripts/db-schema.sh <command> [args]

Commands:
  tables                     List all tables in the WordPress database
  describe <table>           Full column/type/key/nullable/default definition
  sample <table> [N]         Show N sample rows (default: 5)
  indexes <table>            Show all indexes on a table
  search <pattern>           Find tables whose name matches SQL LIKE pattern (e.g. '%options%')

Examples:
  ./scripts/db-schema.sh tables
  ./scripts/db-schema.sh describe wmos7_options
  ./scripts/db-schema.sh sample wmos7_posts 3
  ./scripts/db-schema.sh indexes wmos7_postmeta
  ./scripts/db-schema.sh search '%wmos%'
USAGE
  exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in

  tables)
    echo "=== Tables in $DB_NAME ==="
    _db_query "SHOW TABLES;"
    ;;

  describe)
    _require_table "${1:-}"
    TABLE="$1"
    echo "=== Schema: $TABLE ==="
    _db_query "DESCRIBE \`$TABLE\`;"
    echo ""
    echo "=== CREATE TABLE ==="
    _db_query "SHOW CREATE TABLE \`$TABLE\`\G" 2>/dev/null | grep -v "^\*" || true
    ;;

  sample)
    _require_table "${1:-}"
    TABLE="$1"
    N="${2:-5}"
    echo "=== Sample rows from $TABLE (limit $N) ==="
    _db_query "SELECT * FROM \`$TABLE\` LIMIT $N\G" 2>/dev/null || \
      _db_query "SELECT * FROM \`$TABLE\` LIMIT $N;"
    ;;

  indexes)
    _require_table "${1:-}"
    TABLE="$1"
    echo "=== Indexes on $TABLE ==="
    _db_query "SHOW INDEX FROM \`$TABLE\`;"
    ;;

  search)
    if [[ -z "${1:-}" ]]; then
      echo "Error: search pattern required (use SQL LIKE syntax, e.g. '%wmos%')." >&2
      exit 1
    fi
    PATTERN="$1"
    echo "=== Tables matching: $PATTERN ==="
    _db_query "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_NAME LIKE '$PATTERN' ORDER BY TABLE_NAME;"
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Run ./scripts/db-schema.sh with no arguments to see usage." >&2
    exit 1
    ;;

esac
