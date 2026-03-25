#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
WP_PORT="8080"
PMA_PORT="8081"
WP7_PORT="8090"
PMA7_PORT="8091"

cd "$REPO_ROOT"

if [[ -f "$ENV_FILE" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      WP7_PORT) WP7_PORT="$value" ;;
      PMA7_PORT) PMA7_PORT="$value" ;;
    esac
  done < <(grep -E '^(WP7_PORT|PMA7_PORT)=' "$ENV_FILE" || true)
fi

check_http() {
  local label="$1"
  local url="$2"
  local required="$3"

  if command -v curl >/dev/null 2>&1; then
    if curl -fsS "$url" >/dev/null; then
      echo "$label HTTP OK: $url"
    else
      echo "$label HTTP check failed for $url" >&2
      if [[ "$required" == "1" ]]; then
        exit 1
      fi
    fi
  fi
}

check_stack() {
  local service="$1"
  local wp_port="$2"
  local pma_service="$3"
  local pma_port="$4"
  local required="$5"

  if ! docker compose ps --status running --services 2>/dev/null | grep -qx "$service"; then
    if [[ "$required" == "1" ]]; then
      echo "$service service is not running." >&2
      exit 1
    fi
    echo "$service service is not running. Skipping optional sandbox checks."
    return
  fi

  echo "$service container is running."

  check_http "$service" "http://localhost:${wp_port}" "$required"
  check_http "$service admin" "http://localhost:${wp_port}/wp-admin" "$required"

  if docker compose ps --status running --services 2>/dev/null | grep -qx "$pma_service"; then
    check_http "$pma_service" "http://localhost:${pma_port}" "0"
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI not found. Cannot verify local WordPress health." >&2
  exit 2
fi

echo "== Docker Compose Services =="
docker compose ps
echo

check_stack "wordpress7" "$WP7_PORT" "phpmyadmin7" "$PMA7_PORT" "1"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found. Container status verified, HTTP checks skipped."
fi