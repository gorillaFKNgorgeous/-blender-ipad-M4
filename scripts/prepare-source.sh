#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(dirname "$SCRIPT_DIR")"
IOS_PATCH="$HARNESS_DIR/patches/ios-5.2-m4-full.patch"

SOURCE_DIR="${1:-$PWD/work/blender}"
UPSTREAM_URL="${BLENDER_UPSTREAM_URL:-https://github.com/salmazov/blender-ios.git}"
PINNED_BLENDER_REF="2bc556e58e82eb3a801895f2cb1881c0267e5cd5"
PINNED_IOS_LIB_REF="393201c7c8525941553f6a96e19b909d6b3bfc4f"
PINNED_MACOS_LIB_REF="a3e20428fb0ab2231903608cdca90301e130dbfc"
BLENDER_REF="${BLENDER_REF:-$PINNED_BLENDER_REF}"
BUNDLE_ID="${BUNDLE_ID:-com.gorillafkngorgeous.blenderipad52}"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "This build must run on an Apple-silicon macOS host." >&2
  exit 1
fi

for command in git git-lfs cmake xcodebuild plutil brew; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

# The build-machine CPython 3.13.13 needs macOS libffi headers for its native _ctypes
# module. Keep this strictly a host-tool dependency: do not export CPPFLAGS, LDFLAGS,
# PKG_CONFIG_PATH, or any other Homebrew path into the workflow environment. Homebrew's
# libffi is keg-only, so force-link its headers and pkg-config metadata into the ordinary
# Homebrew prefix where the later host configure can discover it. The iOS CPython build
# disables pkg-config and supplies its own iOS LIBFFI_CFLAGS/LIBFFI_LIBS explicitly.
if ! brew list --versions libffi >/dev/null 2>&1; then
  brew install libffi
fi
host_libffi_prefix="$(brew --prefix libffi)"
brew link --overwrite --force libffi >/dev/null
brew_prefix="$(brew --prefix)"
test -f "$host_libffi_prefix/include/ffi.h"
test -e "$brew_prefix/include/ffi.h"
test -e "$brew_prefix/lib/pkgconfig/libffi.pc"
echo "Host-only libffi headers prepared at $host_libffi_prefix"

# cibuildwheel deliberately sanitizes iOS build environments so macOS/Homebrew libraries
# cannot leak into target wheels. zstandard's isolated build installs CFFI, whose setup.py
# needs ffi.h and resolves -lffi itself. Give every iOS wheel sandbox the already-planned
# target libffi location. These paths do not need to exist yet; external_ffi is built before
# NumPy/zstandard are invoked. The platform-specific setting takes precedence over each
# generic CIBW_ENVIRONMENT value while remaining invisible to native macOS builds.
#
# IPHONEOS_DEPLOYMENT_TARGET must also exist in the outer GitHub Actions environment.
# cibuildwheel selects the iOS wheel platform tag before it enters the sanitized target
# environment, so keeping the value only inside CIBW_ENVIRONMENT_IOS can produce an ios_13_0
# filename even when the extension itself is compiled with -target arm64-apple-ios26.0.
if [[ -n "${GITHUB_ENV:-}" && -n "${GITHUB_WORKSPACE:-}" ]]; then
  ios_libffi_root="$GITHUB_WORKSPACE/work/deps-ios-bootstrap/Release/ffi"
  printf '%s\n' \
    "IPHONEOS_DEPLOYMENT_TARGET=26.0" \
    "CIBW_ENVIRONMENT_IOS=RUNNER_OS=macOS RUNNER_ARCH=ARM64 INSTALL_OPENBLAS=false IPHONEOS_DEPLOYMENT_TARGET=26.0 CFLAGS='-I${ios_libffi_root}/include' LDFLAGS='-L${ios_libffi_root}/lib'" \
    "CIBW_CONFIG_SETTINGS=--global-option=--no-cffi-backend" \
    >> "$GITHUB_ENV"
  echo "Configured outer iOS deployment target for cibuildwheel tag selection: 26.0"
  echo "Configured iOS-only cibuildwheel libffi search paths: $ios_libffi_root"
  echo "Configured zstandard cibuildwheel to use its native CPython C backend only"
fi

if [[ ! -f "$IOS_PATCH" ]]; then
  echo "Missing Blender 5.2 iPad compatibility patch: $IOS_PATCH" >&2
  exit 1
fi
if [[ -e "$SOURCE_DIR" ]]; then
  echo "Source destination already exists: $SOURCE_DIR" >&2
  exit 1
fi
if [[ "$BLENDER_REF" != "$PINNED_BLENDER_REF" ]]; then
  echo "BLENDER_REF must match the audited Blender 5.2 iOS revision." >&2
  exit 1
fi

mkdir -p "$(dirname "$SOURCE_DIR")"

GIT_LFS_SKIP_SMUDGE=1 git clone \
  --filter=blob:none \
  --no-checkout \
  --single-branch \
  --branch ios-new \
  --depth 1 \
  "$UPSTREAM_URL" \
  "$SOURCE_DIR"

git -C "$SOURCE_DIR" lfs install --local --skip-smudge
git -C "$SOURCE_DIR" fetch --no-tags --depth 1 origin "$BLENDER_REF"

actual_blender_ref="$(git -C "$SOURCE_DIR" rev-parse FETCH_HEAD)"
if [[ "$actual_blender_ref" != "$BLENDER_REF" ]]; then
  echo "Pinned Blender 5.2 revision mismatch: $actual_blender_ref" >&2
  exit 1
fi

git -C "$SOURCE_DIR" checkout --detach "$actual_blender_ref"
git -C "$SOURCE_DIR" lfs pull origin

# These submodules opt out of ordinary updates. --checkout is therefore required.
GIT_LFS_SKIP_SMUDGE=0 git -C "$SOURCE_DIR" submodule update \
  --init \
  --checkout \
  --depth 1 \
  lib/ios_arm64 \
  lib/macos_arm64

actual_ios_lib_ref="$(git -C "$SOURCE_DIR/lib/ios_arm64" rev-parse HEAD)"
actual_macos_lib_ref="$(git -C "$SOURCE_DIR/lib/macos_arm64" rev-parse HEAD)"
if [[ "$actual_ios_lib_ref" != "$PINNED_IOS_LIB_REF" ]]; then
  echo "Pinned iOS library revision mismatch: $actual_ios_lib_ref" >&2
  exit 1
fi
if [[ "$actual_macos_lib_ref" != "$PINNED_MACOS_LIB_REF" ]]; then
  echo "Pinned macOS library revision mismatch: $actual_macos_lib_ref" >&2
  exit 1
fi

git -C "$SOURCE_DIR/lib/ios_arm64" lfs pull
git -C "$SOURCE_DIR/lib/macos_arm64" lfs pull

# Apply only the audited compatibility delta. The old 5.1 input patch is deliberately not
# applied wholesale because 5.2 has newer keyboard, Pencil, pointer, and GCMouse code.
git -C "$SOURCE_DIR" apply --check "$IOS_PATCH"
git -C "$SOURCE_DIR" apply "$IOS_PATCH"
git -C "$SOURCE_DIR" diff --check

version_header="$SOURCE_DIR/source/blender/blenkernel/BKE_blender_version.h"
input_system="$SOURCE_DIR/intern/ghost/intern/GHOST_SystemIOS.mm"
input_window="$SOURCE_DIR/intern/ghost/intern/GHOST_WindowIOS.mm"
info_plist="$SOURCE_DIR/release/ios/Blender.app/Info.plist"
bundle_script="$SOURCE_DIR/release/ios/scripts/copy_bundle_data.sh"

grep -Eq '^#define BLENDER_VERSION +502$' "$version_header"
grep -Eq '^#define BLENDER_VERSION_PATCH +0$' "$version_header"
grep -Eq '^#define BLENDER_VERSION_CYCLE +release$' "$version_header"
grep -Fq 'GHOST_SystemIOS::setPointerButtonState' "$input_system"
test "$(grep -Fc -- '- (void)pushIndirectPointerCursorEvent' "$input_window")" -eq 1
method_line="$(grep -n -m1 -- '- (void)pushIndirectPointerCursorEvent' "$input_window" | cut -d: -f1)"
generator_line="$(grep -n -m1 -- '- (void)generateUserInputEvents' "$input_window" | cut -d: -f1)"
test "$method_line" -lt "$generator_line"
grep -Fq 'physical_memory >= (12ull * 1024ull * 1024ull * 1024ull)' \
  "$SOURCE_DIR/source/blender/gpu/metal/mtl_backend.mm"
test -d "$SOURCE_DIR/scripts/addons_core/bl_pkg"
if grep -Fq 'Removing bl_pkg addon' "$bundle_script"; then
  echo "The extension manager would be removed from the app bundle." >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c 'Print :UIApplicationSupportsIndirectInputEvents' "$info_plist" | \
  grep -Fxq true

if /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Blender 5.2 iPad' "$info_plist"
else
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Blender 5.2 iPad' "$info_plist"
fi

# Preserve the increased-memory entitlement in source. A separately packaged Signulous fallback
# strips it only from that copy; the M4/full-memory artifact remains unthrottled.
/usr/libexec/PlistBuddy \
  -c 'Print :com.apple.developer.kernel.increased-memory-limit' \
  "$SOURCE_DIR/release/ios/entitlements.plist" | grep -Fxq true

cat <<EOF
Prepared Blender 5.2 LTS iPad source.
Blender revision: $actual_blender_ref
iOS libraries: $actual_ios_lib_ref
macOS host libraries: $actual_macos_lib_ref
Bundle identifier: $BUNDLE_ID
Compatibility patch SHA-256: $(shasum -a 256 "$IOS_PATCH" | awk '{print $1}')
EOF
