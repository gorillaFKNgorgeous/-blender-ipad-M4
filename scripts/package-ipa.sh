#!/usr/bin/env bash

set -Eeuo pipefail

BUILD_DIR="${1:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA [full-memory|signulous]}"
OUTPUT_IPA="${2:?Usage: package-ipa.sh BUILD_DIR OUTPUT_IPA [full-memory|signulous]}"
PROFILE="${3:-full-memory}"
EXPECTED_BUNDLE_ID="${BUNDLE_ID:-com.gorillafkngorgeous.blenderipad52}"
ASSET_FILE_MIN="${ASSET_FILE_MIN:-2500}"
FULL_MEMORY_ENTITLEMENTS="${FULL_MEMORY_ENTITLEMENTS:-}"

on_error() {
  local status=$?
  local line="${BASH_LINENO[0]:-unknown}"
  echo "::error::package-ipa.sh failed at line $line: $BASH_COMMAND" >&2
  exit "$status"
}
trap on_error ERR

fail() {
  echo "::error::$*" >&2
  return 1
}

require_file() {
  local path="$1"
  local label="${2:-required file}"
  [[ -f "$path" ]] || fail "$label is missing: $path"
  echo "Verified $label: $path"
}

require_dir() {
  local path="$1"
  local label="${2:-required directory}"
  [[ -d "$path" ]] || fail "$label is missing: $path"
  echo "Verified $label: $path"
}

require_nonempty() {
  local value="$1"
  local label="$2"
  [[ -n "$value" ]] || fail "$label was not found"
  echo "Verified $label: $value"
}

require_match() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  grep -F "$needle" <<< "$haystack" >/dev/null || fail "$label did not contain: $needle"
  echo "Verified $label contains: $needle"
}

if [[ -z "$FULL_MEMORY_ENTITLEMENTS" && -n "${SOURCE_DIR:-}" ]]; then
  FULL_MEMORY_ENTITLEMENTS="$SOURCE_DIR/release/ios/entitlements.plist"
fi
require_file "$FULL_MEMORY_ENTITLEMENTS" "full-memory entitlements plist"

if [[ "$PROFILE" != "full-memory" && "$PROFILE" != "signulous" ]]; then
  fail "Unknown package profile: $PROFILE"
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
echo "Packaging app bundle: $app_path"

plist="$app_path/Info.plist"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
asset_file_count="$(find "$app_path/Assets" -type f | wc -l | tr -d ' ')"

[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || \
  fail "Unexpected bundle identifier: $bundle_id (expected $EXPECTED_BUNDLE_ID)"
[[ "$short_version" == 5.2* ]] || fail "Unexpected Blender version: $short_version"
if (( asset_file_count < ASSET_FILE_MIN )); then
  fail "Blender.app contains only $asset_file_count asset files; expected at least $ASSET_FILE_MIN"
fi
echo "Verified bundle identity, version, and $asset_file_count asset files"

python_os="$(find "$app_path/Assets" -type f -path '*/python/lib/python3.13/os.py' -print -quit)"
bl_pkg="$(find "$app_path/Assets" -type f -path '*/scripts/addons_core/bl_pkg/__init__.py' -print -quit)"
cycles_props="$(find "$app_path/Assets" -type f -path '*/scripts/addons_core/cycles/properties.py' -print -quit)"
cycles_kernel="$(find "$app_path/Assets" -type f -path '*/scripts/addons_core/cycles/source/kernel/*.h' -print -quit)"
usd_asset="$(find "$app_path/Assets" -type f \
  \( -path '*/datafiles/usd/*.json' -o -path '*/datafiles/usd/*.usda' \) -print -quit)"
usd_dylib="$(find "$app_path/Assets/lib" -type f -name 'libusd_ms.dylib' -print -quit)"
openvdb_dylib="$(find "$app_path/Assets/lib" -type f -name 'libopenvdb.dylib' -print -quit)"
oidn_dylib="$(find "$app_path/Assets/lib" -type f -name 'libOpenImageDenoise.dylib' -print -quit)"
numpy_init="$(find "$app_path/Assets" -type f \
  -path '*/python/lib/python3.13/site-packages/numpy/__init__.py' -print -quit)"
numpy_fwork="$(find "$app_path/Assets" -type f \
  -path '*/python/lib/python3.13/site-packages/numpy/*.fwork' -print -quit)"
requests_init="$(find "$app_path/Assets" -type f \
  -path '*/python/lib/python3.13/site-packages/requests/__init__.py' -print -quit)"
certifi_ca="$(find "$app_path/Assets" -type f \
  -path '*/python/lib/python3.13/site-packages/certifi/cacert.pem' -print -quit)"
zstandard_fwork="$(find "$app_path/Assets" -type f \
  -path '*/python/lib/python3.13/site-packages/zstandard/*.fwork' -print -quit)"
draco_marker="$(find "$app_path/Assets" -type f \
  -path '*/scripts/addons_core/io_scene_gltf2/libbf_intern_draco_bridge.fwork' -print -quit)"
meshopt_marker="$(find "$app_path/Assets" -type f \
  -path '*/scripts/addons_core/io_scene_gltf2/libbf_intern_meshopt_bridge.fwork' -print -quit)"

require_nonempty "$python_os" "Python 3.13 standard library"
require_nonempty "$bl_pkg" "bl_pkg add-on"
require_nonempty "$cycles_props" "Cycles add-on"
require_nonempty "$cycles_kernel" "Cycles kernel sources"
require_nonempty "$usd_asset" "USD runtime data"
require_dir "$app_path/Assets/lib/materialx" "MaterialX runtime libraries"
require_nonempty "$usd_dylib" "USD shared library"
require_nonempty "$openvdb_dylib" "OpenVDB shared library"
require_nonempty "$oidn_dylib" "OpenImageDenoise shared library"
require_file "$app_path/Frameworks/Python.framework/Python" "Python.framework binary"
require_nonempty "$numpy_init" "NumPy package"
require_nonempty "$numpy_fwork" "NumPy framework marker"
require_nonempty "$requests_init" "requests package"
require_nonempty "$certifi_ca" "certifi CA bundle"
require_nonempty "$zstandard_fwork" "zstandard framework marker"
require_nonempty "$draco_marker" "Draco glTF bridge framework marker"
require_nonempty "$meshopt_marker" "meshoptimizer glTF bridge framework marker"

loose_codec_dylib="$(find "$app_path/Assets/lib" -type f \
  \( -iname '*draco*.dylib*' -o -iname '*meshoptimizer*.dylib*' \) -print -quit)"
if [[ -n "$loose_codec_dylib" ]]; then
  fail "Codec dependency escaped its bridge framework as a loose dylib: $loose_codec_dylib"
fi
echo "Verified Draco and meshoptimizer codec dependencies are not loose app dylibs"

framework_count="$(find "$app_path/Frameworks" -type d -name '*.framework' | wc -l | tr -d ' ')"
if (( framework_count < 4 )); then
  fail "Expected Python, extension, Draco, and meshoptimizer frameworks; found $framework_count"
fi
unconverted_extension="$(find "$app_path" -type f -name '*.so' -print -quit)"
if [[ -n "$unconverted_extension" ]]; then
  fail "The app bundle contains an unconverted Python .so outside an iOS framework: $unconverted_extension"
fi

# A clean bundle is the expected case. Test each small file directly so grep's
# "no match" status (1) is harmless while actual read errors (>1) still fail.
lfs_pointers=""
while IFS= read -r -d '' candidate; do
  set +e
  grep -Il '^version https://git-lfs.github.com/spec/v1$' "$candidate" >/dev/null
  grep_status=$?
  set -e
  if (( grep_status == 0 )); then
    lfs_pointers+="${lfs_pointers:+$'\n'}$candidate"
  elif (( grep_status != 1 )); then
    fail "Git LFS pointer scan failed for $candidate with status $grep_status"
  fi
done < <(find "$app_path/Assets" -type f -size -200c -print0)
if [[ -n "$lfs_pointers" ]]; then
  echo "The app bundle contains unresolved Git LFS pointer files." >&2
  printf '%s\n' "$lfs_pointers" >&2
  exit 1
fi
echo "Verified app bundle contains no unresolved Git LFS pointers"

# Every .fwork marker must resolve from the marker's enclosing .app, not from sys.executable.
# Its framework binary must be an iOS Mach-O, signed, and paired with a reverse .origin record.
fwork_count=0
while IFS= read -r marker; do
  [[ -n "$marker" ]] || continue
  fwork_count=$((fwork_count + 1))
  marker_relative="${marker#"$app_path"/}"
  framework_relative="$(cat "$marker")"
  framework_relative="${framework_relative//$'\r'/}"
  framework_relative="${framework_relative//$'\n'/}"

  [[ -n "$framework_relative" ]] || fail "Empty .fwork marker: $marker"
  case "$framework_relative" in
    Frameworks/*.framework/*) ;;
    *) fail "Invalid .fwork target '$framework_relative' in $marker" ;;
  esac
  if [[ "$framework_relative" == *"/../"* || "$framework_relative" == "../"* || \
        "$framework_relative" == *"/.." || "$framework_relative" == /* ]]; then
    fail "Unsafe .fwork target '$framework_relative' in $marker"
  fi

  framework_binary="$app_path/$framework_relative"
  framework_dir="${framework_binary%/*}"
  origin_file="$framework_binary.origin"
  require_file "$framework_binary" "framework target for $marker_relative"
  require_file "$origin_file" "origin record for $marker_relative"

  origin_relative="$(cat "$origin_file")"
  origin_relative="${origin_relative//$'\r'/}"
  origin_relative="${origin_relative//$'\n'/}"
  [[ "$origin_relative" == "$marker_relative" ]] || \
    fail "Origin mismatch for $framework_relative: '$origin_relative' != '$marker_relative'"

  vtool_output="$(xcrun vtool -show-build "$framework_binary")"
  require_match "$vtool_output" "platform IOS" "iOS build metadata for $framework_relative"
  codesign --verify --strict "$framework_dir"
  if otool -L "$framework_binary" | sed -n '2,$p' | \
    grep -E '/opt/homebrew|/Users/runner|MacOSX\.sdk' >/dev/null
  then
    echo "Host-only linkage detected in $framework_binary:" >&2
    otool -L "$framework_binary" >&2
    exit 1
  fi
  echo "Verified .fwork mapping: $marker_relative -> $framework_relative"
done < <(find "$app_path/Assets" -type f -name '*.fwork' -print)

if (( fwork_count == 0 )); then
  fail "No .fwork framework markers were found in the application bundle"
fi
echo "Verified $fwork_count .fwork marker/origin pairs"

draco_bridge_relative="$(cat "$draco_marker")"
draco_bridge_relative="${draco_bridge_relative//$'\r'/}"
draco_bridge_relative="${draco_bridge_relative//$'\n'/}"
draco_bridge="$app_path/$draco_bridge_relative"
meshopt_bridge_relative="$(cat "$meshopt_marker")"
meshopt_bridge_relative="${meshopt_bridge_relative//$'\r'/}"
meshopt_bridge_relative="${meshopt_bridge_relative//$'\n'/}"
meshopt_bridge="$app_path/$meshopt_bridge_relative"

if otool -L "$draco_bridge" | sed -n '2,$p' | grep -Ei 'libdraco[^/]*\.dylib' >/dev/null; then
  echo "Draco bridge still depends on a runtime Draco dylib:" >&2
  otool -L "$draco_bridge" >&2
  exit 1
fi
if otool -L "$meshopt_bridge" | sed -n '2,$p' | grep -Ei 'libmeshoptimizer[^/]*\.dylib' >/dev/null; then
  echo "meshoptimizer bridge still depends on a runtime meshoptimizer dylib:" >&2
  otool -L "$meshopt_bridge" >&2
  exit 1
fi
echo "Verified glTF bridges contain their codec dependencies without loose dylib linkage"

file "$app_path/$executable"
main_lipo="$(lipo -info "$app_path/$executable")"
require_match "$main_lipo" "arm64" "main executable architecture"
main_loads="$(otool -L "$app_path/$executable")"
require_match "$main_loads" "@rpath/Python.framework/Python" "main executable linkage"
main_commands="$(otool -l "$app_path/$executable")"
require_match "$main_commands" "@executable_path/Frameworks" "main executable runpath"
require_match "$main_commands" "@loader_path/Assets/lib" "main executable runpath"
python_build="$(xcrun vtool -show-build "$app_path/Frameworks/Python.framework/Python")"
require_match "$python_build" "platform IOS" "Python.framework build metadata"

while IFS= read -r framework; do
  framework_name="$(basename "$framework" .framework)"
  framework_binary="$framework/$framework_name"
  require_file "$framework_binary" "framework binary"
  framework_build="$(xcrun vtool -show-build "$framework_binary")"
  require_match "$framework_build" "platform IOS" "framework build metadata for $framework_name"
  codesign --verify --strict "$framework"
done < <(find "$app_path/Frameworks" -type d -name '*.framework' -print)
plutil -lint "$plist"

stage_dir="$(mktemp -d)"
cleanup_stage() {
  rm -rf "$stage_dir"
}
trap cleanup_stage EXIT
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
    fail "Restricted memory entitlement remains in the Signulous signing set"
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
    fail "Restricted memory entitlement was embedded in the Signulous fallback"
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
  fail "IPA contains only $archive_entries entries; refusing incomplete archive"
fi

echo "Packaged unsigned IPA: $OUTPUT_IPA"
echo "Profile: $PROFILE"
echo "Bundle identifier: $bundle_id"
echo "Version: $short_version"
echo "Bundled asset files: $asset_file_count"
echo "Framework markers: $fwork_count"
echo "Archive entries: $archive_entries"
du -sh "$app_path" "$OUTPUT_IPA"
shasum -a 256 "$OUTPUT_IPA"
