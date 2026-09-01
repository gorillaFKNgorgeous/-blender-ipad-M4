#!/usr/bin/env bash
#
# verify-app-linkage.sh - embed Python.framework and prove every @rpath
# dependency in Blender.app resolves before an IPA is ever packaged.
#
# Why this exists
# ---------------
# Run 33457455632 produced a green build whose IPA died in dyld at launch:
#
#   termination: namespace DYLD, "Library missing"
#   Library not loaded: @rpath/Python.framework/Python
#   tried: .../Blender.app/Assets/lib/Python.framework/Python          (no such file)
#          .../Blender.app/Frameworks;@loader_path/Assets/lib/...      (no such file)
#
# The second path is one literal directory name. CMAKE_XCODE_ATTRIBUTE_* values
# are written into the Xcode project verbatim - they do NOT go through CMake's
# list semantics - and Xcode splits LD_RUNPATH_SEARCH_PATHS on WHITESPACE, not
# semicolons. So the two intended rpaths became a single nonsense LC_RPATH.
#
# Build-time linking used FRAMEWORK_SEARCH_PATHS and was fine, which is why
# every existing gate passed: they checked that files exist and that otool -L
# MENTIONS @rpath/Python.framework/Python. Nothing checked that the reference
# RESOLVES. That is what this script does.
#
# Two workflow edits go with it
# -----------------------------
# 1) In "Configure full Blender 5.2 iPad profile", replace the semicolon with a
#    space (add $(inherited) so Xcode's own default survives):
#
#      -DCMAKE_XCODE_ATTRIBUTE_LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks @loader_path/Assets/lib" \
#
# 2) Add this step immediately BEFORE "Package full-memory and Signulous
#    fallback IPAs" - it must run before signing, because anything copied into
#    the bundle has to be inside the ad-hoc signature:
#
#      - name: Embed and verify Python.framework
#        run: bash ./scripts/verify-app-linkage.sh "$BUILD_DIR" "$SOURCE_DIR"
#
# It writes $ARTIFACT_DIR/Blender-iPad-M4-5.2-bundle-manifest.txt, which your
# existing diagnostics glob (artifacts/*manifest.txt) already uploads. Your
# current manifests describe build INPUTS; this one describes what actually
# landed in the .app, so the next failure is diagnosable without a device.
#
# Usage: verify-app-linkage.sh [BUILD_DIR] [SOURCE_DIR]
#        (falls back to the $BUILD_DIR / $SOURCE_DIR environment variables)
#
# Kept compatible with bash 3.2 - macOS runners do not reliably provide bash 5.

set -euo pipefail

BUILD_DIR="${1:-${BUILD_DIR:-}}"
SOURCE_DIR="${2:-${SOURCE_DIR:-}}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PWD/artifacts}"
PYTHON_FRAMEWORK_SRC="${PYTHON_FRAMEWORK_SRC:-$SOURCE_DIR/lib/ios_arm64/python/Python.framework}"

MANIFEST="$ARTIFACT_DIR/Blender-iPad-M4-5.2-bundle-manifest.txt"

die() { echo "::error::$*" >&2; exit 1; }
note() { echo "::notice::$*"; }
warn() { echo "::warning::$*"; }

[ -n "$BUILD_DIR" ] || die "BUILD_DIR not set (pass as \$1 or export it)"
[ -d "$BUILD_DIR" ] || die "BUILD_DIR does not exist: $BUILD_DIR"

APP="$(find "$BUILD_DIR" -maxdepth 6 -type d -name 'Blender.app' -print -quit)"
[ -n "$APP" ] || die "no Blender.app found under $BUILD_DIR"
BIN="$APP/Blender"
[ -f "$BIN" ] || die "no main executable at $BIN"
note "app bundle: $APP"

mkdir -p "$ARTIFACT_DIR"

# ---------------------------------------------------------------------------
# 1. Embed Python.framework if the build did not
# ---------------------------------------------------------------------------
FW="$APP/Frameworks/Python.framework"

if [ -f "$FW/Python" ]; then
  note "Python.framework already embedded by the build"
  EMBED_STATUS="present-from-build"
else
  warn "Python.framework was NOT embedded by the build - copying it in"
  warn "  (this means the rpath was only half the bug: the framework was missing too)"
  [ -d "$PYTHON_FRAMEWORK_SRC" ] || die "no source framework at $PYTHON_FRAMEWORK_SRC"

  mkdir -p "$APP/Frameworks"
  rm -rf "$FW"
  # -L dereferences symlinks, so a macOS-style Versions/Current/Python symlink
  # becomes a real binary instead of a dangling pointer once we flatten.
  cp -RL "$PYTHON_FRAMEWORK_SRC" "$FW"
  # iOS frameworks must be FLAT. A Versions/ tree is a macOS layout and is
  # rejected by device install validation.
  rm -rf "$FW/Versions"
  # A flat iOS framework carries Info.plist at its root, not under Resources/.
  if [ ! -f "$FW/Info.plist" ] && [ -f "$FW/Resources/Info.plist" ]; then
    cp "$FW/Resources/Info.plist" "$FW/Info.plist"
  fi
  [ -f "$FW/Python" ] || die "copy produced no $FW/Python - check the source layout"
  # Ad-hoc sign what we just added; package-ipa.sh re-signs the bundle after us,
  # and Signulous re-signs everything downstream, but an unsigned nested Mach-O
  # is its own launch failure and not worth risking.
  codesign --force --sign - "$FW" >/dev/null 2>&1 || warn "ad-hoc sign of $FW failed"
  EMBED_STATUS="copied-by-this-script"
fi

xcrun vtool -show-build "$FW/Python" | grep -F 'platform IOS' >/dev/null \
  || die "$FW/Python is not an iOS Mach-O - wrong slice was embedded"
note "Python.framework binary is iOS arm64"

# ---------------------------------------------------------------------------
# 2. Collect every Mach-O in the bundle
# ---------------------------------------------------------------------------
# .fwork files are plain-text markers, not Mach-O, so they drop out here - which
# is correct, they are resolved by the loader shim, not by dyld search paths.
MACHO_LIST="$(mktemp "${TMPDIR:-/tmp}/blender-machos.XXXXXX")"
trap 'rm -f "$MACHO_LIST"' EXIT

find "$APP" -type f -print0 \
  | xargs -0 file 2>/dev/null \
  | grep -F 'Mach-O' \
  | sed 's/: *Mach-O.*//' > "$MACHO_LIST"

MACHO_COUNT="$(grep -c . "$MACHO_LIST" || true)"
note "Mach-O binaries in bundle: $MACHO_COUNT"
[ "$MACHO_COUNT" -gt 0 ] || die "no Mach-O binaries found in $APP - bundle is not what we think it is"

rpaths_of() {  # $1 = mach-o path -> one LC_RPATH per line
  otool -l "$1" 2>/dev/null | awk '/cmd LC_RPATH/{c=1} c && /^ *path /{print $2; c=0}'
}

rpath_deps_of() {  # $1 = mach-o -> one @rpath/@loader_path/@executable_path dep per line
  otool -L "$1" 2>/dev/null | awk 'NR>1 && $1 ~ /^@/ {print $1}'
}

# ---------------------------------------------------------------------------
# 3. Verify: no malformed rpaths, and every @-relative dependency resolves
# ---------------------------------------------------------------------------
{
  echo "Blender iPad 5.2 bundle manifest"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "App: ${APP#"$BUILD_DIR"/}"
  echo "Python.framework: $EMBED_STATUS"
  echo "Mach-O binaries: $MACHO_COUNT"
  echo
  echo "Top-level bundle entries"
  ls -1 "$APP"
  echo
  echo "Embedded frameworks"
  find "$APP" -maxdepth 3 -name '*.framework' -type d | sed "s|^$APP/||" | sort
  echo
  echo "Linkage"
} > "$MANIFEST"

fail=0

# Redirected on the `done` so the loop body runs in THIS shell and `fail` sticks.
while IFS= read -r macho; do
  [ -n "$macho" ] || continue
  loader_dir="$(dirname "$macho")"
  rel_name="${macho#"$APP"/}"

  echo "  $rel_name" >> "$MANIFEST"

  # 3a. malformed LC_RPATH - the exact bug that shipped in run 33457455632
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    echo "    LC_RPATH $r" >> "$MANIFEST"
    case "$r" in
      *";"*)
        echo "::error::$rel_name: semicolon-joined LC_RPATH, Xcode never split it: $r"
        fail=1
        ;;
    esac
  done <<EOF
$(rpaths_of "$macho")
EOF

  # 3b. every @-relative dependency must resolve against this binary's rpaths
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    echo "    needs    $dep" >> "$MANIFEST"
    resolved=0
    case "$dep" in
      @rpath/*)
        dep_rel="${dep#@rpath/}"
        while IFS= read -r r; do
          [ -n "$r" ] || continue
          base="$r"
          base="${base//@executable_path/$APP}"
          base="${base//@loader_path/$loader_dir}"
          if [ -f "$base/$dep_rel" ]; then resolved=1; break; fi
        done <<EOF
$(rpaths_of "$macho")
EOF
        ;;
      @executable_path/*|@loader_path/*)
        base="$dep"
        base="${base//@executable_path/$APP}"
        base="${base//@loader_path/$loader_dir}"
        [ -f "$base" ] && resolved=1
        ;;
      *)
        resolved=1  # absolute system path, the dyld shared cache handles it
        ;;
    esac
    if [ "$resolved" != 1 ]; then
      echo "::error::$rel_name: unresolvable at runtime: $dep"
      fail=1
    fi
  done <<EOF
$(rpath_deps_of "$macho")
EOF
done < "$MACHO_LIST"

if [ "$fail" != 0 ]; then
  echo "::error::bundle would crash in dyld at launch - refusing to package an IPA"
  echo "::notice::see $MANIFEST for the full linkage dump"
  exit 1
fi

note "every @rpath dependency in the bundle resolves"
note "bundle manifest written to $MANIFEST"
