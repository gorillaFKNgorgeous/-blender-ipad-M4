#!/usr/bin/env bash

set -Eeuo pipefail

BUILD_DIR="${1:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA [full-memory|signulous]}"
OUTPUT_IPA="${2:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA [full-memory|signulous]}"
PROFILE="${3:-full-memory}"
EXPECTED_BUNDLE_ID="${BUNDLE_ID:-com.gorillafkngorgeous.blenderipad52}"
ASSET_FILE_MIN="${ASSET_FILE_MIN:-2500}"

if [[ "$PROFILE" != "full-memory" && "$PROFILE" != "signulous" ]]; then
  echo "Unknown package profile: $PROFILE" >&2
  exit 1
fi

app_path=""
while IFS= read -r candidate; do
  plist="$candidate/Info.plist"
  [[ -f "$plist" ]] || continue
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
  [[ -n "$executable" && -f "$candidate/$executable" ]] || continue

  assets_dir="$candidate/Assets"
  ui_startup_script="$(find "$assets_dir" -type f -path '*/scripts/startup/bl_ui/__init__.py' -print -quit 2>/dev/null || true)"
  bundled_blend_asset="$(find "$assets_dir" -type f -name '*.blend' -path '*/datafiles/assets/*' -print -quit 2>/dev/null || true)"
  if [[ ! -d "$assets_dir" || -z "$ui_startup_script" || -z "$bundled_blend_asset" ]]; then
    echo "Ignoring incomplete app bundle: $candidate" >&2
    continue
  fi

  app_path="$candidate"
  break
done < <(find "$BUILD_DIR" -type d -name 'Blender.app' -print)

if [[ -z "$app_path" ]]; then
  echo "No complete Blender.app found below $BUILD_DIR" >&2
  find "$BUILD_DIR" -maxdepth 6 -type d -name '*.app' -print >&2 || true
  exit 1
fi

plist="$app_path/Info.plist"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
asset_file_count="$(find "$app_path/Assets" -type f | wc -l | tr -d ' ')"

[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]]
[[ "$short_version" == 5.2* ]]
if (( asset_file_count < ASSET_FILE_MIN )); then
  echo "Blender.app contains only $asset_file_count asset files; expected at least $ASSET_FILE_MIN" >&2
  exit 1
fi

test -f "$(find "$app_path/Assets" -path '*/python/lib/python3.13/os.py' -print -quit)"
test -f "$(find "$app_path/Assets" -path '*/scripts/addons_core/bl_pkg/__init__.py' -print -quit)"
test -f "$(find "$app_path/Assets" -path '*/scripts/addons_core/cycles/properties.py' -print -quit)"
test -n "$(find "$app_path/Assets" -path '*/scripts/addons_core/cycles/source/kernel/*.h' -print -quit)"
test -n "$(find "$app_path/Assets" -path '*/datafiles/usd/*.json' -o -path '*/datafiles/usd/*.usda' -print -quit)"
test -d "$app_path/Assets/lib/materialx"
test -n "$(find "$app_path/Assets/lib" -name 'libusd_ms.dylib' -print -quit)"
test -n "$(find "$app_path/Assets/lib" -name 'libopenvdb.dylib' -print -quit)"
test -n "$(find "$app_path/Assets/lib" -name 'libOpenImageDenoise.dylib' -print -quit)"

if find "$app_path/Assets" -type f -size -200c -exec grep -Il \
  '^version https://git-lfs.github.com/spec/v1$' {} + | grep -q .; then
  echo "The app bundle contains unresolved Git LFS pointer files." >&2
  exit 1
fi

file "$app_path/$executable"
lipo -info "$app_path/$executable" | grep -Fq arm64
plutil -lint "$plist"

stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT
mkdir -p "$stage_dir/Payload" "$(dirname "$OUTPUT_IPA")"
cp -R "$app_path" "$stage_dir/Payload/Blender.app"
staged_app="$stage_dir/Payload/Blender.app"
xattr -cr "$staged_app" || true

if [[ "$PROFILE" == "signulous" ]]; then
  # Ordinary sideloading profiles cannot carry Apple's restricted increased-memory entitlement.
  # Only this fallback copy is stripped; the full-memory artifact retains the capability request.
  /usr/libexec/PlistBuddy \
    -c 'Delete :com.apple.developer.kernel.increased-memory-limit' \
    "$staged_app/Info.plist" >/dev/null 2>&1 || true
  if /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.developer.kernel.increased-memory-limit' \
    "$staged_app/Info.plist" >/dev/null 2>&1; then
    echo "Restricted memory entitlement key remains in Signulous profile." >&2
    exit 1
  fi
else
  /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.developer.kernel.increased-memory-limit' \
    "$staged_app/Info.plist" | grep -Fxq true
fi

(
  cd "$stage_dir"
  ditto -c -k --sequesterRsrc --keepParent Payload "$OUTPUT_IPA"
)

archive_entries="$(unzip -Z1 "$OUTPUT_IPA" | wc -l | tr -d ' ')"
if (( archive_entries < ASSET_FILE_MIN )); then
  echo "IPA contains only $archive_entries entries; refusing incomplete archive." >&2
  exit 1
fi

echo "Packaged unsigned IPA: $OUTPUT_IPA"
echo "Profile: $PROFILE"
echo "Bundle identifier: $bundle_id"
echo "Version: $short_version"
echo "Bundled asset files: $asset_file_count"
echo "Archive entries: $archive_entries"
du -sh "$app_path" "$OUTPUT_IPA"
shasum -a 256 "$OUTPUT_IPA"
