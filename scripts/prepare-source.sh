#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_DIR="${1:-$PWD/work/blender}"
UPSTREAM_URL="${BLENDER_UPSTREAM_URL:-https://projects.blender.org/blender/blender.git}"
IOS_5_1_2_SHA="${IOS_5_1_2_SHA:-a1de44dd54af75a4c8c4a29a5fed2a1334a87446}"
BLENDER_REF="${BLENDER_REF:-$IOS_5_1_2_SHA}"
BUNDLE_ID="${BUNDLE_ID:-com.gorillafkngorgeous.blenderipad}"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "This build must run on an Apple-silicon macOS host." >&2
  exit 1
fi

for command in git git-lfs cmake xcodebuild plutil; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

if [[ -e "$SOURCE_DIR" ]]; then
  echo "Source destination already exists: $SOURCE_DIR" >&2
  exit 1
fi

if [[ "$BLENDER_REF" != "$IOS_5_1_2_SHA" ]]; then
  echo "BLENDER_REF must match the verified Blender iOS 5.1.2 revision." >&2
  exit 1
fi

mkdir -p "$(dirname "$SOURCE_DIR")"

git clone \
  --filter=blob:none \
  --no-checkout \
  --branch ios \
  --depth 1 \
  "$UPSTREAM_URL" \
  "$SOURCE_DIR"

git -C "$SOURCE_DIR" lfs install --local --skip-smudge
git -C "$SOURCE_DIR" fetch --no-tags --depth 1 origin "$BLENDER_REF"

actual_blender_ref="$(git -C "$SOURCE_DIR" rev-parse FETCH_HEAD)"
if [[ "$actual_blender_ref" != "$BLENDER_REF" ]]; then
  echo "Pinned Blender iOS 5.1.2 revision mismatch: $actual_blender_ref" >&2
  exit 1
fi

git -C "$SOURCE_DIR" checkout --detach "$actual_blender_ref"
git -C "$SOURCE_DIR" lfs pull origin

(
  cd "$SOURCE_DIR"
  ./build_files/utils/make_update.py \
    --no-blender \
    --use-ios-libraries \
    --architecture arm64
)

info_plist="$SOURCE_DIR/release/ios/Blender.app/Info.plist"
entitlements="$SOURCE_DIR/release/ios/entitlements.plist"
creator_cmake="$SOURCE_DIR/source/creator/CMakeLists.txt"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$info_plist"

if /usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$info_plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Blender iPad" "$info_plist"
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Blender iPad" "$info_plist"
fi

# This entitlement requires a matching Apple provisioning profile. Removing it
# allows an unsigned artifact to be re-signed by ordinary sideloading tools.
/usr/libexec/PlistBuddy \
  -c "Delete :com.apple.developer.kernel.increased-memory-limit" \
  "$entitlements" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy \
  -c "Delete :com.apple.developer.kernel.increased-memory-limit" \
  "$info_plist" >/dev/null 2>&1 || true

# Blender's iOS install step normally re-signs bundled libraries with the
# developer identity from the local macOS keychain. GitHub's unsigned build has
# no such identity; the complete bundle is signed after the IPA is built.
# Keep the upstream behavior by default and skip only that block when the cloud
# build opts in with -DBLENDER_IOS_SKIP_INSTALL_CODESIGN=ON.
codesign_guard_matches="$(perl -0ne '
  while (/if\(WITH_APPLE_CROSSPLATFORM\)(?=.{0,1000}codesign)/sg) { $count++ }
  END { print $count || 0 }
' "$creator_cmake")"

if [[ "$codesign_guard_matches" != "1" ]]; then
  echo "Expected one iOS install-time codesign block, found $codesign_guard_matches" >&2
  exit 1
fi

perl -0pi -e '
  s/if\(WITH_APPLE_CROSSPLATFORM\)(?=.{0,1000}codesign)/if(WITH_APPLE_CROSSPLATFORM AND NOT BLENDER_IOS_SKIP_INSTALL_CODESIGN)/s
' "$creator_cmake"

grep -Fq \
  'if(WITH_APPLE_CROSSPLATFORM AND NOT BLENDER_IOS_SKIP_INSTALL_CODESIGN)' \
  "$creator_cmake"

echo "Prepared Blender iOS 5.1.2 source at $SOURCE_DIR"
echo "Blender revision: $actual_blender_ref"
echo "Bundle identifier: $BUNDLE_ID"
