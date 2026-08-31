#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match in {path}, found {count}")
    if new in text:
        raise RuntimeError(f"{label}: replacement already present in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Applied {label}: {path}")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: apply-ios-codec-frameworks.py BLENDER_SOURCE_DIR")
    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        raise RuntimeError(f"Blender source directory does not exist: {root}")

    p = root / "build_files/build_environment/cmake/draco.cmake"
    replace_once(p,
        "set(DRACO_EXTRA_ARGS\n  -DBUILD_SHARED_LIBS=ON\n)\n",
        """if(WITH_APPLE_CROSSPLATFORM)
  # Keep the loadable glTF bridge dynamic, but fold Draco into it on iOS.
  set(DRACO_EXTRA_ARGS
    -DBUILD_SHARED_LIBS=OFF
  )
else()
  set(DRACO_EXTRA_ARGS
    -DBUILD_SHARED_LIBS=ON
  )
endif()
""", "static iOS Draco dependency")
    replace_once(p,
        """  harvest_rpath_lib(external_draco draco/lib draco/lib "*${SHAREDLIBEXT}*")
  # Draco unconditionally builds as a static library, harvest it to satisfy the CMake config target.
  harvest(external_draco draco/lib draco/lib "*.a")
""",
        """  if(WITH_APPLE_CROSSPLATFORM)
    harvest(external_draco draco/lib draco/lib "*.a")
  else()
    harvest_rpath_lib(external_draco draco/lib draco/lib "*${SHAREDLIBEXT}*")
    harvest(external_draco draco/lib draco/lib "*.a")
  endif()
""", "iOS Draco static harvest")

    p = root / "build_files/build_environment/cmake/meshoptimizer.cmake"
    replace_once(p,
        "set(MESHOPTIMIZER_EXTRA_ARGS\n  -DMESHOPT_BUILD_SHARED_LIBS=ON\n)\n",
        """if(WITH_APPLE_CROSSPLATFORM)
  # Keep the loadable glTF bridge dynamic, but fold meshoptimizer into it on iOS.
  set(MESHOPTIMIZER_EXTRA_ARGS
    -DMESHOPT_BUILD_SHARED_LIBS=OFF
  )
else()
  set(MESHOPTIMIZER_EXTRA_ARGS
    -DMESHOPT_BUILD_SHARED_LIBS=ON
  )
endif()
""", "static iOS meshoptimizer dependency")
    replace_once(p,
        '  harvest_rpath_lib(external_meshoptimizer meshoptimizer/lib meshoptimizer/lib "*${SHAREDLIBEXT}*")\n',
        """  if(WITH_APPLE_CROSSPLATFORM)
    harvest(external_meshoptimizer meshoptimizer/lib meshoptimizer/lib "*.a")
  else()
    harvest_rpath_lib(external_meshoptimizer meshoptimizer/lib meshoptimizer/lib "*${SHAREDLIBEXT}*")
  endif()
""", "iOS meshoptimizer static harvest")

    p = root / "intern/draco_bridge/CMakeLists.txt"
    replace_once(p,
        """if(WITH_APPLE_CROSSPLATFORM)
  # Use static lib to resolve nested signing issues on cross-platform device builds.
  add_library(bf_intern_draco_bridge STATIC "${SRC}")
else()
  add_library(bf_intern_draco_bridge SHARED "${SRC}")
endif()
""",
        """# The glTF add-on opens this target through ctypes. The codec dependency is static on iOS.
add_library(bf_intern_draco_bridge SHARED "${SRC}")
""", "loadable iOS Draco bridge")
    replace_once(p, "if(APPLE AND NOT WITH_APPLE_CROSSPLATFORM)\n", "if(APPLE)\n",
                 "Draco bridge Xcode install guard")

    p = root / "intern/meshoptimizer_bridge/CMakeLists.txt"
    replace_once(p,
        """if(WITH_APPLE_CROSSPLATFORM)
  # Use static lib to resolve nested signing issues on cross-platform device builds.
  add_library(bf_intern_meshopt_bridge STATIC "${SRC}")
else()
  add_library(bf_intern_meshopt_bridge SHARED "${SRC}")
endif()
""",
        """# The glTF add-on opens this target through ctypes. The codec dependency is static on iOS.
add_library(bf_intern_meshopt_bridge SHARED "${SRC}")
""", "loadable iOS meshoptimizer bridge")
    replace_once(p, "if(APPLE AND NOT WITH_APPLE_CROSSPLATFORM)\n", "if(APPLE)\n",
                 "meshoptimizer bridge Xcode install guard")

    p = root / "source/creator/CMakeLists.txt"
    replace_once(p,
        """    add_executable(blender ${EXETYPE} ${SRC} ${storyboards} ${asset_catalog})

    # Additional libraries required by static python extensions compiled directly in source.
""",
        """    add_executable(blender ${EXETYPE} ${SRC} ${storyboards} ${asset_catalog})

    # The glTF add-on loads these bridges at runtime, so build them before app bundling.
    if(WITH_DRACO)
      add_dependencies(blender bf_intern_draco_bridge)
    endif()
    if(WITH_MESHOPTIMIZER)
      add_dependencies(blender bf_intern_meshopt_bridge)
    endif()

    # Additional libraries required by static python extensions compiled directly in source.
""", "iOS app codec bridge dependencies")

    p = root / "release/ios/scripts/copy_bundle_data.sh"
    replace_once(p,
        '  plutil -insert CFBundlePackageType -string APPL "$info_plist"\n',
        '  plutil -insert CFBundlePackageType -string FMWK "$info_plist"\n',
        "framework package type")
    replace_once(p,
        """UNCONVERTED_EXTENSION="$(find "$APP_BUNDLE" -type f -name '*.so' -print -quit)"
if [ -n "$UNCONVERTED_EXTENSION" ]; then
  echo "Unconverted Python extension remains outside Frameworks: $UNCONVERTED_EXTENSION" >&2
  exit 1
fi

echo "Signing embedded Python frameworks..."
""",
        """UNCONVERTED_EXTENSION="$(find "$APP_BUNDLE" -type f -name '*.so' -print -quit)"
if [ -n "$UNCONVERTED_EXTENSION" ]; then
  echo "Unconverted Python extension remains outside Frameworks: $UNCONVERTED_EXTENSION" >&2
  exit 1
fi

install_gltf_bridge() {
  local bridge_source="$1"
  local bridge_name="$2"
  local addon_dir="$DEST/scripts/addons_core/io_scene_gltf2"
  local marker="$addon_dir/lib${bridge_name}.fwork"
  local marker_relative="${marker#"$APP_BUNDLE"/}"
  local framework_folder="Frameworks/$bridge_name.framework"
  local framework_dir="$APP_BUNDLE/$framework_folder"
  local framework_binary="$framework_dir/$bridge_name"
  local safe_bridge_name="${bridge_name//_/-}"

  test -f "$bridge_source"
  mkdir -p "$addon_dir" "$framework_dir"
  create_extension_plist "$framework_dir/Info.plist" "$bridge_name" \
    "${PRODUCT_BUNDLE_IDENTIFIER:-org.blenderfoundation.blender}.$safe_bridge_name"
  cp -f "$bridge_source" "$framework_binary"
  chmod +x "$framework_binary"
  install_name_tool -id "@rpath/$bridge_name.framework/$bridge_name" "$framework_binary"
  printf '%s\n' "$framework_folder/$bridge_name" > "$marker"
  printf '%s\n' "$marker_relative" > "$framework_binary.origin"
}

find_bridge_binary() {
  find "$BUILD_DIR" -type f -name "lib$1*.dylib" -print -quit
}

DRACO_BRIDGE="$(find_bridge_binary bf_intern_draco_bridge)"
MESHOPT_BRIDGE="$(find_bridge_binary bf_intern_meshopt_bridge)"
[ -n "$DRACO_BRIDGE" ] || { echo "Missing built iOS Draco bridge below $BUILD_DIR" >&2; exit 1; }
[ -n "$MESHOPT_BRIDGE" ] || { echo "Missing built iOS meshoptimizer bridge below $BUILD_DIR" >&2; exit 1; }
install_gltf_bridge "$DRACO_BRIDGE" bf_intern_draco_bridge
install_gltf_bridge "$MESHOPT_BRIDGE" bf_intern_meshopt_bridge

for bridge_binary in \
  "$FRAMEWORKS_DIR/bf_intern_draco_bridge.framework/bf_intern_draco_bridge" \
  "$FRAMEWORKS_DIR/bf_intern_meshopt_bridge.framework/bf_intern_meshopt_bridge"
do
  xcrun vtool -show-build "$bridge_binary" | grep -F 'platform IOS' >/dev/null
done

echo "Signing embedded Python frameworks..."
""", "package glTF codec bridges as frameworks")

    p = root / "scripts/addons_core/io_scene_gltf2/io/com/library.py"
    replace_once(p,
        "from pathlib import Path\n\n\ndef dll_path(lib_name, lib_display_name) -> Path | None:\n",
        """from pathlib import Path


def _ios_framework_path(marker: Path, lib_display_name: str) -> Path | None:
    # Resolve the marker from its enclosing .app so Blender's executable location is irrelevant.
    if not marker.exists() or not marker.is_file():
        return marker
    try:
        framework_relative = marker.read_text(encoding='utf-8').strip()
    except OSError as ex:
        print('ERROR', '{} framework marker could not be read: {}'.format(lib_display_name, ex))
        return None
    if not framework_relative or os.path.isabs(framework_relative):
        print('ERROR', '{} has an invalid framework marker at {}'.format(lib_display_name, marker.absolute()))
        return None
    app_bundle = next((parent for parent in marker.parents if parent.suffix == '.app'), None)
    if app_bundle is None:
        print('ERROR', '{} framework marker is not inside an app bundle: {}'.format(lib_display_name, marker.absolute()))
        return None
    app_bundle = app_bundle.resolve(strict=False)
    framework = (app_bundle / framework_relative).resolve(strict=False)
    try:
        framework.relative_to(app_bundle)
    except ValueError:
        print('ERROR', '{} framework marker escapes the app bundle: {}'.format(lib_display_name, marker.absolute()))
        return None
    return framework


def dll_path(lib_name, lib_display_name) -> Path | None:
""", "iOS glTF framework resolver")
    replace_once(p,
        "        'linux': 'lib{}.so'.format(lib_name),\n        'darwin': 'lib{}.dylib'.format(lib_name)\n",
        "        'linux': 'lib{}.so'.format(lib_name),\n        'darwin': 'lib{}.dylib'.format(lib_name),\n        'ios': 'lib{}.fwork'.format(lib_name),\n",
        "iOS glTF library marker name")
    replace_once(p,
        """    else:
        base = os.path.dirname(sys.modules['io_scene_gltf2'].__file__)
    return Path(os.path.join(base, library_name))
""",
        """    else:
        base = os.path.dirname(sys.modules['io_scene_gltf2'].__file__)
    path = Path(os.path.join(base, library_name))
    if sys.platform == 'ios':
        return _ios_framework_path(path, lib_display_name)
    return path
""", "iOS glTF marker resolution")
    replace_once(p,
        "    path = dll_path(lib_name, lib_display_name)\n    exists = (path is not None) and (path.exists() and path.is_file())\n",
        """    path = dll_path(lib_name, lib_display_name)
    if path is None:
        print('ERROR', '{} is not available because its location could not be determined'.format(lib_display_name))
        return False
    exists = path.exists() and path.is_file()
""", "graceful missing glTF codec capability")

    print("iOS codec framework source transform completed successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
