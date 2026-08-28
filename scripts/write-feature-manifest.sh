#!/usr/bin/env bash

set -Eeuo pipefail

CACHE_FILE="${1:?Usage: write-feature-manifest.sh CMakeCache.txt OUTPUT.txt}"
OUTPUT_FILE="${2:?Usage: write-feature-manifest.sh CMakeCache.txt OUTPUT.txt}"

required_on=(
  WITH_PYTHON
  WITH_CYCLES
  WITH_CYCLES_DEVICE_METAL
  WITH_CODEC_FFMPEG
  WITH_ALEMBIC
  WITH_OPENVDB
  WITH_OPENIMAGEDENOISE
  WITH_USD
  WITH_AUDASPACE
  WITH_OPENAL
  WITH_CODEC_SNDFILE
  WITH_DRACO
  WITH_MESHOPTIMIZER
  WITH_OPENSUBDIV
  WITH_INTERNATIONAL
)

platform_blocked=(
  WITH_HYDRA
  WITH_XR_OPENXR
  WITH_CYCLES_OSL
)

for feature in "${required_on[@]}"; do
  if ! grep -Eq "^${feature}:BOOL=ON$" "$CACHE_FILE"; then
    echo "Required 5.2 iPad feature is not enabled: $feature" >&2
    grep -E "^${feature}:" "$CACHE_FILE" >&2 || true
    exit 1
  fi
done

for feature in "${platform_blocked[@]}"; do
  if ! grep -Eq "^${feature}:BOOL=OFF$" "$CACHE_FILE"; then
    echo "Expected platform-blocked feature has changed state: $feature" >&2
    grep -E "^${feature}:" "$CACHE_FILE" >&2 || true
    exit 1
  fi
done

mkdir -p "$(dirname "$OUTPUT_FILE")"
{
  echo "Blender iPad 5.2 feature manifest"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Source: ${BLENDER_REF:-unknown}"
  echo "Target: iPadOS 26 minimum; tested target iPadOS 27 / 1 TB M4"
  echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo
  echo "Required enabled features"
  for feature in "${required_on[@]}"; do
    grep -E "^${feature}:BOOL=" "$CACHE_FILE"
  done
  echo
  echo "Platform-blocked features (backend/runtime absent)"
  for feature in "${platform_blocked[@]}"; do
    grep -E "^${feature}:BOOL=" "$CACHE_FILE"
  done
  echo
  echo "Complete WITH_* cache"
  grep -E '^WITH_[A-Z0-9_]+:(BOOL|STRING)=' "$CACHE_FILE" | LC_ALL=C sort
} > "$OUTPUT_FILE"

cat "$OUTPUT_FILE"
