#!/usr/bin/env bash

set -Eeuo pipefail

BUILD_DIR="${1:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA}"
OUTPUT_IPA="${2:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA}"

app_path=""
while IFS= read -r candidate; do
  plist="$candidate/Info.plist"
  [[ -f "$plist" ]] || continue
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
  [[ -n "$executable" && -f "$candidate/$executable" ]] || continue

  assets_dir="$candidate/Assets"
  ui_startup_script="$(find "$assets_dir" -type f -path '*/scripts/startup/bl_ui/__init__.py' -print -quit 2>/dev/null || true)"
  bundled_blend_asset="$(find "$assets_dir" -type f -name '*.blend' -path '*/datafiles/assets/*' -print -quit 2>/dev/null || true)"

  # The iOS target compiles startup.blend into the executable, so validate the
  # installed UI startup scripts and bundled .blend assets instead.
  if [[ ! -d "$assets_dir" || -z "$ui_startup_script" || -z "$bundled_blend_asset" ]]; then
    echo "Ignoring incomplete app bundle: $candidate" >&2
    continue
  fi

  app_path="$candidate"
  break
done < <(find "$BUILD_DIR" -type d \( -name 'Blender.app' -o -name 'blender.app' \) -print)

if [[ -z "$app_path" ]]; then
  echo "No complete Blender.app with executable, UI startup scripts, and bundled .blend assets found below $BUILD_DIR" >&2
  find "$BUILD_DIR" -maxdepth 5 -type d -name '*.app' -print >&2 || true
  exit 1
fi

plist="$app_path/Info.plist"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
asset_file_count="$(find "$app_path/Assets" -type f | wc -l | tr -d ' ')"

if (( asset_file_count < 100 )); then
  echo "Blender.app contains only $asset_file_count asset files; refusing to package an incomplete installation" >&2
  exit 1
fi

file "$app_path/$executable"
lipo -info "$app_path/$executable"
plutil -lint "$plist"

stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT
mkdir -p "$stage_dir/Payload" "$(dirname "$OUTPUT_IPA")"
cp -R "$app_path" "$stage_dir/Payload/Blender.app"
xattr -cr "$stage_dir/Payload/Blender.app" || true

(
  cd "$stage_dir"
  ditto -c -k --sequesterRsrc --keepParent Payload "$OUTPUT_IPA"
)

echo "Packaged unsigned IPA: $OUTPUT_IPA"
echo "Bundle identifier: $bundle_id"
echo "Bundled asset files: $asset_file_count"
du -sh "$app_path" "$OUTPUT_IPA"
shasum -a 256 "$OUTPUT_IPA"
