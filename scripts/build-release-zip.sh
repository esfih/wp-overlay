#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/build-release-zip.sh --source <plugin-source-dir> --plugin-slug <plugin-slug> --version <version> --bootstrap <bootstrap-file>
EOF
}

SOURCE=""
PLUGIN_SLUG=""
VERSION=""
BOOTSTRAP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --plugin-slug)
      PLUGIN_SLUG="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --bootstrap)
      BOOTSTRAP="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$SOURCE" || -z "$PLUGIN_SLUG" || -z "$VERSION" || -z "$BOOTSTRAP" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$SOURCE" ]]; then
  echo "ERROR: source folder not found: $SOURCE" >&2
  exit 2
fi

mkdir -p output/releases
OUT_ZIP="output/releases/${PLUGIN_SLUG}-${VERSION}.zip"

python - "$SOURCE" "$PLUGIN_SLUG" "$OUT_ZIP" <<'PY'
from __future__ import annotations
import os
import sys
import zipfile

source = os.path.abspath(sys.argv[1])
slug = sys.argv[2]
out_zip = os.path.abspath(sys.argv[3])

exclude_dirs = {'.git', '.github', '__pycache__', '.idea', '.vscode'}
exclude_files = {'.DS_Store'}

with zipfile.ZipFile(out_zip, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(source):
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        rel_root = os.path.relpath(root, source)
        if rel_root == '.':
            rel_root = ''

        # Keep explicit folder entries for compatibility with some hosts.
        if rel_root:
            folder_arc = f"{slug}/{rel_root.replace(os.sep, '/')}/"
            zf.writestr(folder_arc, b"")
        else:
            zf.writestr(f"{slug}/", b"")

        for file_name in files:
            if file_name in exclude_files:
                continue
            full_path = os.path.join(root, file_name)
            rel_file = os.path.join(rel_root, file_name) if rel_root else file_name
            arcname = f"{slug}/{rel_file.replace(os.sep, '/')}"
            zf.write(full_path, arcname)

print(out_zip)
PY

python scripts/verify-release-zip-paths.py "$OUT_ZIP" --plugin-slug "$PLUGIN_SLUG" --bootstrap "$BOOTSTRAP"

echo "Built: $OUT_ZIP"
