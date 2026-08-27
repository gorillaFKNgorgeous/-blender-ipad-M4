#!/usr/bin/env bash

set -Eeuo pipefail

BUILD_DIR="${1:?Usage: install-ghostblender-bridge.sh BUILD_DIR}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(dirname "$SCRIPT_DIR")"
BRIDGE_SOURCE="$HARNESS_DIR/blender/ghostblender_bridge.py"

if [[ ! -f "$BRIDGE_SOURCE" ]]; then
  echo "Missing GhostBlender bridge source: $BRIDGE_SOURCE" >&2
  exit 1
fi

python3 -m py_compile "$BRIDGE_SOURCE"

startup_dir=""
while IFS= read -r bl_ui; do
  candidate="$(dirname "$(dirname "$bl_ui")")"
  if [[ -d "$candidate" ]]; then
    startup_dir="$candidate"
    break
  fi
done < <(find "$BUILD_DIR" -type f -path '*/Assets/*/scripts/startup/bl_ui/__init__.py' -print)

if [[ -z "$startup_dir" ]]; then
  echo "Could not locate Blender's installed startup scripts below $BUILD_DIR" >&2
  exit 1
fi

install -m 0644 "$BRIDGE_SOURCE" "$startup_dir/ghostblender_bridge.py"
test -f "$startup_dir/ghostblender_bridge.py"
grep -Fq 'BRIDGE_VERSION = "0.1.0"' "$startup_dir/ghostblender_bridge.py"

echo "Installed GhostBlender startup bridge: $startup_dir/ghostblender_bridge.py"
