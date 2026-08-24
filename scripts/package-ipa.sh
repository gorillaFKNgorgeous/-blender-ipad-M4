#!/usr/bin/env bash

set -Eeuo pipefail

BUILD_DIR="${1:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA}"
OUTPUT_IPA="${2:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA}"

app_path=""
while IFS= read -r candidate; do
  plist="$candidate/Info.plist"
  [[ -f "$plist" ]] || continue
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
  if [[ -n "$executable" && -f "$candidate/$executable" ]]; then
    app_path="$candidate"
    break
  fi
done < <(find "$BUILD_DIR" -type d \( -name 'Blender.app' -o -name 'blender.app' \) -print)

if [[ -z "$app_path" ]]; then
  echo "No complete Blender.app found below $BUILD_DIR" >&2
  find "$BUILD_DIR" -maxdepth 5 -type d -name '*.app' -print >&2 || true
  exit 1
fi

plist="$app_path/Info.plist"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"

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
shasum -a 256 "$OUTPUT_IPA"
