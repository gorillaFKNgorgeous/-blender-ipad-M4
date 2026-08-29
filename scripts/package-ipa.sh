#!/usr/bin/env bash

set -Eeuo pipefail

BUILD_DIR="${1:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA [full-memory|signulous]}"
OUTPUT_IPA="${2:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA [full-memory|signulous]}"
PROFILE="${3:-full-memory}"
EXPECTED_BUNDLE_ID="${BUNDLE_ID:-com.gorillafkngorgeous.blenderipad52}"
ASSET_FILE_MIN="${ASSET_FILE_MIN:-2500}"
FULL_MEMORY_ENTITLEMENTS="${FULL_MEMORY_ENTITLEMENTS:-}"

if [[ -z "$FULL_MEMORY_ENTITLEMENTS" && -n "${SOURCE_DIR:-}" ]]; then
  FULL_MEMORY_ENTITLEMENTS="$SOURCE_DIR/release/ios/entitlements.plist"
fi
if [[ ! -f "$FULL_MEMORY_ENTITLEMENTS" ]]; then
  echo "Missing full-memory entitlements plist: $FULL_MEMORY_ENTITLEMENTS" >&2
  exit 1
fi

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
  find "$BUILD_DIR" -type d -name '*.app' -print >&2 || true
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
test -f "$app_path/Frameworks/Python.framework/Python"
test -f "$(find "$app_path/Assets" \
  -path '*/python/lib/python3.13/site-packages/numpy/__init__.py' -print -quit)"
test -n "$(find "$app_path/Assets" \
  -path '*/python/lib/python3.13/site-packages/numpy/*.fwork' -print -quit)"
test -f "$(find "$app_path/Assets" \
  -path '*/python/lib/python3.13/site-packages/requests/__init__.py' -print -quit)"
test -f "$(find "$app_path/Assets" \
  -path '*/python/lib/python3.13/site-packages/certifi/cacert.pem' -print -quit)"
test -n "$(find "$app_path/Assets" \
  -path '*/python/lib/python3.13/site-packages/zstandard/*.fwork' -print -quit)"

meshoptimizer_dylib="$(find "$app_path/Assets/lib" -type f \
  -name 'libmeshoptimizer*.dylib*' -print -quit)"
if [[ -z "$meshoptimizer_dylib" ]]; then
  echo "Blender.app is missing its bundled meshoptimizer dylib." >&2
  find "$app_path/Assets/lib" -maxdepth 1 -type f -print >&2 || true
  exit 1
fi
xcrun vtool -show-build "$meshoptimizer_dylib" | grep -F 'platform IOS' >/dev/null
codesign --verify --strict "$meshoptimizer_dylib"

python_framework_count="$(find "$app_path/Frameworks" -type d -name '*.framework' | wc -l | tr -d ' ')"
if (( python_framework_count < 2 )); then
  echo "Expected Python.framework and NumPy extension frameworks; found $python_framework_count" >&2
  exit 1
fi
unconverted_extension="$(find "$app_path" -type f -name '*.so' -print -quit)"
if [[ -n "$unconverted_extension" ]]; then
  echo "The app bundle contains an unconverted Python .so outside an iOS framework." >&2
  exit 1
fi

lfs_pointers="$(find "$app_path/Assets" -type f -size -200c -exec grep -Il \
  '^version https://git-lfs.github.com/spec/v1$' {} +)"
if [[ -n "$lfs_pointers" ]]; then
  echo "The app bundle contains unresolved Git LFS pointer files." >&2
  printf '%s\n' "$lfs_pointers" >&2
  exit 1
fi

file "$app_path/$executable"
lipo -info "$app_path/$executable" | grep -F arm64 >/dev/null
otool -L "$app_path/$executable" | grep -F '@rpath/Python.framework/Python' >/dev/null
otool -L "$app_path/$executable" | grep -F 'libmeshoptimizer' >/dev/null
otool -l "$app_path/$executable" | grep -F '@executable_path/Frameworks' >/dev/null
otool -l "$app_path/$executable" | grep -F '@loader_path/Assets/lib' >/dev/null
xcrun vtool -show-build "$app_path/Frameworks/Python.framework/Python" | \
  grep -F 'platform IOS' >/dev/null
while IFS= read -r framework; do
  framework_name="$(basename "$framework" .framework)"
  test -f "$framework/$framework_name"
  xcrun vtool -show-build "$framework/$framework_name" | grep -F 'platform IOS' >/dev/null
  codesign --verify --strict "$framework"
done < <(find "$app_path/Frameworks" -type d -name '*.framework' -print)
plutil -lint "$plist"

stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT
mkdir -p "$stage_dir/Payload" "$(dirname "$OUTPUT_IPA")"
cp -R "$app_path" "$stage_dir/Payload/Blender.app"
staged_app="$stage_dir/Payload/Blender.app"
xattr -cr "$staged_app" || true
signing_entitlements="$stage_dir/signing-entitlements.plist"
embedded_entitlements="$stage_dir/embedded-entitlements.plist"
cp "$FULL_MEMORY_ENTITLEMENTS" "$signing_entitlements"

if [[ "$PROFILE" == "signulous" ]]; then
  # Ordinary sideloading profiles cannot carry Apple's restricted increased-memory entitlement.
  # Strip it from this copy's actual code-signing entitlements, not from Info.plist.
  /usr/libexec/PlistBuddy \
    -c 'Delete :com.apple.developer.kernel.increased-memory-limit' \
    "$signing_entitlements" >/dev/null 2>&1 || true
  if /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.developer.kernel.increased-memory-limit' \
    "$signing_entitlements" >/dev/null 2>&1; then
    echo "Restricted memory entitlement remains in the Signulous signing set." >&2
    exit 1
  fi
else
  /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.developer.kernel.increased-memory-limit' \
    "$signing_entitlements" | grep -Fx true >/dev/null
fi

# Ad-hoc signing embeds the requested entitlement set and seals the completed bundle without
# provisioning it. Signulous (or another service/profile) can then replace this handoff signature.
codesign --force --sign - --timestamp=none \
  --entitlements "$signing_entitlements" \
  "$staged_app"
codesign --verify --deep --strict "$staged_app"
codesign -d --entitlements :- "$staged_app" \
  > "$embedded_entitlements" 2>/dev/null
plutil -lint "$embedded_entitlements"
if [[ "$PROFILE" == "signulous" ]]; then
  if /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.developer.kernel.increased-memory-limit' \
    "$embedded_entitlements" >/dev/null 2>&1; then
    echo "Restricted memory entitlement was embedded in the Signulous fallback." >&2
    exit 1
  fi
else
  /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.developer.kernel.increased-memory-limit' \
    "$embedded_entitlements" | grep -Fx true >/dev/null
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
