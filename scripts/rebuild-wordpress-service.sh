#!/usr/bin/env bash
set -euo pipefail

# Rebuild + restart local WordPress service and run a minimal readiness probe.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Building wordpress image..."
docker compose build wordpress

echo "[2/4] Recreating wordpress container..."
docker compose up -d wordpress

echo "[3/4] Service status..."
docker compose ps wordpress || true

echo "[4/4] REST probe (/index.php/wp-json/)..."
docker compose exec -T wordpress sh -lc 'curl -s -o /tmp/wmos_rest_probe.json -w "%{http_code}\n" http://localhost/index.php/wp-json/ && head -c 220 /tmp/wmos_rest_probe.json && echo'

echo "Done."