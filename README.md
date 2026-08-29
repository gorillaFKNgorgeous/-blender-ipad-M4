# Blender 5.2 LTS for iPad Pro M4

This branch builds a full-capability Blender 5.2 LTS iPad application for an iPad Pro M4 running iPadOS 27. It does not inherit the deliberately reduced 5.1 bring-up profile.

## Reproducible source

- Blender iOS source: [`salmazov/blender-ios`](https://github.com/salmazov/blender-ios/tree/ios-new), pinned at `2bc556e58e82eb3a801895f2cb1881c0267e5cd5`.
- iOS dependency bundle: `393201c7c8525941553f6a96e19b909d6b3bfc4f`.
- macOS host-tool bundle: `a3e20428fb0ab2231903608cdca90301e130dbfc`.
- Minimum deployment target: iPadOS 26.0. The intended device is iPadOS 27 on a 1 TB M4 iPad Pro.

The compatibility patch repairs a malformed Objective-C method placement in the public head, retains queried mouse-button state and indirect pointer declarations from our last working input branch, preserves Blender's extension manager, bundles USD/MaterialX runtime data, and gives high-memory iPads an M4-class shader-compilation policy.

## Capability policy

Configuration fails unless every feature in the enabled column remains `ON`. The generated feature manifest also records every other `WITH_*` setting, so a dependency cannot silently disappear.

| Required in this build | Deliberately blocked by a missing iPad backend/runtime |
|---|---|
| Python 3.13, NumPy 2.3.4, Zstandard, HTTPS packages, and `bl_pkg` | Hydra Storm: pinned USD has no HgiMetal or Storm backend |
| Cycles CPU + Metal, EEVEE, Embree and path guiding | OpenXR: iPadOS has no OpenXR runtime/backend |
| FFmpeg | Cycles OSL: upstream iOS path cannot perform build-time OSL compilation |
| Alembic | |
| OpenVDB | |
| OpenImageDenoise | |
| Core USD import/export and bundled schemas/plugins | |
| Audaspace with OpenAL and libsndfile | |
| Draco and Meshoptimizer | |
| OpenSubdiv and internationalization | |

The public iOS dependency pin contains FFmpeg, Alembic, OpenVDB, OpenImageDenoise, OpenSubdiv, USD, OpenAL, and libsndfile. Its Python runtime is only 3.11, however, while Blender 5.2 and the host tools use Python 3.13. The workflow therefore builds CPython 3.13.13 with its official iOS host triple, compiler wrappers, required `Python.framework`, and static standard-library modules. It also builds NumPy 2.3.4 specifically for `arm64_iphoneos`, using Apple's optimized Accelerate BLAS/LAPACK, and builds the pinned Python Zstandard module needed to read compressed `.blend` data. Blender's pinned requests/certificate packages are restored for HTTPS extension access. Blender links the supported framework; native Python extensions are converted into one signed framework per module with `.fwork` import stubs, following CPython's iOS packaging model. This prevents the public branch's macOS-extension copy from being stripped into a nonfunctional pure-Python shell. Draco and Meshoptimizer are also built for iOS during that bootstrap.

## M4 performance and memory

The public source hard-caps viewport Metal shader compilation at two threads for every iPad because older low-memory devices can be jetsam-killed. This branch keeps that protection below 12 GB, but a 16 GB-class M4/M5 uses its performance cores while leaving one core available for the UI. Serious thermal pressure falls back to the safe two-thread limit.

Cycles already queries live process memory and Metal working-set headroom. Its iOS dispatch-size cap remains because it protects against the iPadOS GPU watchdog timeout; it is not an M2 memory throttle.

## Build and artifacts

Run **Build full Blender 5.2 iPad M4 IPA** from GitHub Actions on branch `upgrade/ios-5.2-m4-full`. The workflow uses an Apple-silicon `macos-15` runner with Xcode 26.3 and builds the `blender` scheme, whose post-build phase creates the complete application bundle.

One artifact contains:

- `Blender-iPad-M4-5.2-full-memory-unsigned.ipa` — embeds the increased-memory capability request for a provisioning profile that supports it.
- `Blender-iPad-M4-5.2-Signulous-unsigned.ipa` — embeds a separate fallback entitlement set without that restricted key for ordinary Signulous-style signing.
- Full-memory entitlements, exact source manifest, and complete CMake feature manifest.

Both IPAs are ad-hoc signed but unprovisioned: the handoff signature seals the finished app and embeds the intended entitlement set, while Signulous or another compatible service supplies the installable signature. Nested Python/NumPy frameworks are also ad-hoc signed. Packaging refuses an incomplete bundle: it checks Blender 5.2, the bundle identifier, Python 3.13, NumPy and its converted iOS frameworks, `bl_pkg`, Cycles Metal kernel sources, USD schemas, MaterialX data, bundled `.blend` assets, key runtime dylibs, arm64 architecture, unresolved Git LFS pointers, minimum asset count, entitlement separation, and archive entry count.

## Current status

The 5.2 workflow is being validated on the isolated upgrade branch. It is not merged into `main`, and the older successful 5.1.2 artifacts remain untouched until the 5.2 build and signed-device launch checks pass.

## Upstream findings carried here

- The public `ios-new` head is based on Blender 5.2.0 LTS and includes newer keyboard, Pencil, Files, pointer, ProMotion, EEVEE, Cycles Metal, and iPadOS work. The old 5.1 desktop-input patch is retained in this repository only as history; applying it wholesale would overwrite newer implementations.
- The public head currently places three Objective-C pointer methods inside `generateUserInputEvents`; the compatibility patch restores their valid position.
- The public setup script checks for Python 3.11, copies host macOS NumPy, and removes `bl_pkg`. This branch supplies supported iOS Python 3.13 plus a real iOS NumPy build and keeps the extension manager.
- Core USD is enabled because the iOS bundle contains the monolithic USD library and runtime data. Hydra remains separate and unavailable because the required rendering backend is absent.

## License

Blender is GPL-licensed. Any distributed modified binary must be accompanied by the corresponding source, this compatibility patch, and the applicable notices.
