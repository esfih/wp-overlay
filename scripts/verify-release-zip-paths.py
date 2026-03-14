#!/usr/bin/env python3
"""Validate WordPress plugin release ZIP path integrity.

Checks:
- archive entries must use forward slashes only
- archive must contain a single top-level plugin folder
- bootstrap file must exist at <plugin-slug>/<bootstrap>
"""

from __future__ import annotations

import argparse
import sys
import zipfile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip_path")
    parser.add_argument("--plugin-slug", required=True)
    parser.add_argument("--bootstrap", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        with zipfile.ZipFile(args.zip_path, "r") as zf:
            names = zf.namelist()
    except FileNotFoundError:
        print(f"ERROR: zip not found: {args.zip_path}")
        return 2
    except zipfile.BadZipFile:
        print(f"ERROR: bad zip file: {args.zip_path}")
        return 2

    if not names:
        print("ERROR: zip is empty")
        return 1

    has_backslash = any("\\" in name for name in names)
    if has_backslash:
        print("ERROR: archive contains backslash path separators")
        return 1

    top_levels = sorted({name.split("/", 1)[0] for name in names if name and not name.startswith("/")})
    expected_top = args.plugin_slug
    if top_levels != [expected_top]:
        print("ERROR: archive must contain exactly one top-level folder")
        print(f"Expected: {expected_top}")
        print(f"Found: {top_levels}")
        return 1

    expected_bootstrap = f"{args.plugin_slug}/{args.bootstrap}"
    if expected_bootstrap not in names:
        print(f"ERROR: missing bootstrap file at {expected_bootstrap}")
        return 1

    print("OK")
    print(f"ZIP: {args.zip_path}")
    print(f"Top-level: {args.plugin_slug}/")
    print(f"Bootstrap: {expected_bootstrap}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
