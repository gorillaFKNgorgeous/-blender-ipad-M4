# Blender on M4 iPad Pro

This repository builds a deliberately narrow, sideloadable Blender prototype for Apple-silicon iPads.

## First milestone

- Blender's official iOS work plus the hardware-keyboard/mouse work from PR `145484`, pinned together at commit `19542aff486fe6db878ecdbc795999d50499406e`.
- That commit is based on Blender's official iOS branch at `2b3dfad92b18185aa518c227a0605f43ce8442db`, avoiding a conflict-prone merge with the newer experimental branch.
- Arm64 iPhoneOS build, tested first on an M4 iPad Pro.
- Metal viewport, Blender's normal desktop interface, Files document access, touch/Pencil support from the upstream branch, and hardware keyboard/mouse input from the pinned PR.
- A smaller bring-up profile: Cycles, video editing dependencies, USD, OpenVDB and other heavyweight modules are disabled until the app launches reliably.

This is not an App Store port and it is not current desktop Blender. The pinned source labels itself Blender 5.0 alpha and remains experimental, with known missing or incomplete platform features.

## Build

Run the **Build unsigned iPad IPA** workflow from GitHub Actions. It uses an Apple-silicon `macos-15` runner and Xcode 16.4, fetches the pinned keyboard/mouse-enabled Blender source and its official precompiled iOS libraries, builds the app, and uploads an unsigned IPA artifact.

An unsigned IPA cannot launch on iPadOS. It must be signed by one of these routes:

1. SideStore or another on-device signer using a personal Apple ID. Free provisioning normally expires after seven days and must be refreshed.
2. A paid Apple Developer account and a CI signing certificate/provisioning profile.
3. TestFlight after enabling the signed-distribution workflow in a later milestone.

The first build intentionally avoids embedding signing credentials in GitHub Actions. We will add exactly one installation route after the unsigned application compiles successfully.

## Build status

GitHub Actions run [`32698659708`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/actions/runs/32698659708) completed successfully on 24 August 2026:

- The application executable is a 64-bit arm64 Mach-O.
- Bundle identifier: `com.gorillafkngorgeous.blenderipad`.
- The executable target compiled, but the resulting IPA omitted Blender's installed `Assets` tree and closes immediately when launched. Do not use that artifact.
- The workflow now builds Blender's `install` target and refuses to package an app without its UI startup scripts, bundled `.blend` assets, and at least 100 asset files. (The iOS target embeds `startup.blend` into the executable.)

## Local macOS build

On an Apple-silicon Mac with Xcode 16.4 selected:

```bash
bash ./scripts/prepare-source.sh "$PWD/work/blender"

cmake -G Xcode \
  -S "$PWD/work/blender" \
  -B "$PWD/work/build-ios" \
  -DAPPLE_TARGET_DEVICE=ios \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DCMAKE_XCODE_GENERATE_SCHEME=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DBLENDER_IOS_SKIP_INSTALL_CODESIGN=ON \
  -DWITH_CYCLES=OFF \
  -DWITH_FFMPEG=OFF \
  -DWITH_OPENVDB=OFF \
  -DWITH_OPENIMAGEDENOISE=OFF \
  -DWITH_USD=OFF \
  -DWITH_HYDRA=OFF \
  -DWITH_INTERNATIONAL=ON

xcodebuild \
  -project "$PWD/work/build-ios/Blender.xcodeproj" \
  -target install \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  build

bash ./scripts/package-ipa.sh "$PWD/work/build-ios" "$PWD/artifacts/Blender-iPad-M4-unsigned.ipa"
```

## Known risks

- Launch behaviour, rendering, keyboard/mouse input, and Files access still require testing on the target iPad after signing a complete build.
- The iOS branch is experimental and development was paused. Some normal Blender functions are absent or unstable.
- The keyboard/mouse PR predates the iOS branch's later Blender 5.1.2 update. Pinning the self-contained PR head gives us a reproducible first build instead of an untested conflict resolution.
- Extensions, add-ons that spawn processes, clipboard images, audio, and some import/export paths may not work.
- Removing the restricted increased-memory entitlement improves sideload compatibility but imposes iPadOS's normal per-app memory limit.
- The unsigned IPA is a build artifact, not an installable release.

## Upstream

- Blender source: <https://projects.blender.org/blender/blender>
- iOS tracking issue: <https://projects.blender.org/blender/blender/issues/142346>
- Hardware keyboard PR: <https://projects.blender.org/blender/blender/pulls/145484>

Blender is GPL-licensed. Any distributed modified Blender binary must be accompanied by the corresponding source and GPL notices.
