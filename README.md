# GhostBlender: Blender on iPad

GhostBlender brings Blender to iPad as a native application, with the ambition of making its creative tools deeply accessible through Siri, an assistant running on the device, and AI agents chosen by the user. The goal is an assistant that understands the open project, carries out substantial work, inspects the result, and helps the user refine it.

This repository contains the workflows, dependency bootstrap, packaging scripts, and compatibility changes used to build a pinned Blender iOS source tree. The current target is **Blender 5.2 on a 1 TB iPad Pro M4 with 16 GB RAM**, running iPadOS 27. The deployment minimum is iPadOS 26.0. This remains an experimental community port.

**Last audited: 6 September 2026.** Native Blender is running on the project device. Siri and the offline assistant are planned; an external-agent bridge exists on a separate, unmerged branch.

## Current project state

| Area | Verified state at this audit |
|---|---|
| Active development | [`upgrade/ios-5.2-m4-full`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/tree/upgrade/ios-5.2-m4-full) |
| Latest successful 5.2 build | [Actions run #81](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/actions/runs/34008472726), completed 6 September 2026 at 04:10 UTC |
| Build harness revision | [`c9b9d486b390`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/commit/c9b9d486b390333e396ba882b33d9a2b6ae591e1), including merged [PR #4: native Open/Save fixes](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/pull/4) |
| Device observations | Earlier 5.2 builds launched with corrected display/touch alignment; scene loading and file insertion were reported working. These observations do not establish acceptance of every operation in build #81. |
| Remaining validation | Save/reopen across Files providers, repeated folder/path nesting, cold/warm document launches, sustained rendering, and unexpected app termination/recovery |
| Default branch | `main` still contains the original 5.0 build harness. Its README is a project overview; select the 5.2 branch to build the current application. |
| Earlier baseline | [`upgrade/ios-5.1.2`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/tree/upgrade/ios-5.1.2) preserves the previously running 5.1.2 build work. |
| External-agent prototype | [PR #3](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/pull/3), `feature/ipad-mcp-bridge`, targets the older `fix/ios-desktop-input` branch. It is absent from build #81. |
| Siri / on-device language model | No App Intents or Foundation Models integration is present in the audited 5.2 harness. |

The supplied 5 September manifests record harness revision `ecf4b8882de2`. This audit also retrieved **run #81's own diagnostics**: its source manifest records `c9b9d486b390`, its feature flags match the supplied manifest, and its bundle manifest records **45 Mach-O binaries**, including `Python.framework`, native NumPy and Zstandard modules, and both glTF codec bridge frameworks. All eight recorded patch hashes match the audited checkout. Keep the harness revision as well as patch hashes: the harness also contains source-transform scripts.

A successful workflow establishes compilation and passage of the configured packaging checks. Feature flags and framework presence do not establish runtime correctness on the signed iPad application.

## Feature coverage

The full profile preserves major Blender capabilities. Configuration fails if any of its **20 required feature flags** becomes disabled. The complete `WITH_*` cache is recorded in the feature manifest.

| Subsystem | Build #81 configuration / packaging evidence |
|---|---|
| Python | CPython **3.13.13**, embedded `Python.framework`, standard library, retained `bl_pkg` extension manager, requests and certificate data |
| Scientific / compression modules | **NumPy 2.3.4** built for iOS with Accelerate ILP64 BLAS/LAPACK; **Zstandard 0.25.0**; native modules packaged as frameworks |
| Rendering | Metal viewport/EEVEE code; Cycles and its Metal device backend enabled; Embree, path guiding, and OpenImageDenoise enabled |
| Scene interchange | USD with schema/plugin data, MaterialX data, Alembic, Draco, and meshoptimizer |
| Volumes / geometry | OpenVDB and OpenSubdiv; the full manifest records the other geometry and simulation options |
| Video / audio | FFmpeg, Audaspace, OpenAL, and libsndfile enabled; the target CoreAudio option is disabled |
| Language support | Internationalization enabled |

Three explicitly blocked features remain **OFF**: Hydra/Storm, because the pinned iOS USD bundle lacks its required HgiMetal/Storm backend; OpenXR, because this port has no iPad runtime/backend; and Cycles OSL, because the pinned iOS build path does not support the required compilation step. Core USD import/export is separate from Hydra rendering.

The extension manager is retained, but compatibility must be established per extension. Bundled iOS Python does not establish support for desktop subprocess workflows or arbitrary desktop native modules.

## Native Files, saving, and stability

| User action | Implemented behavior in the current source transforms |
|---|---|
| **File → Open** | Uses the picker mode that returned selections in device testing, then copies the temporary import once into `Documents/Blender/Imports`. Collisions receive a unique suffix. Edits target that imported copy. |
| **Open in Blender** from Files | Scene-based handoff retains the provider URL for open-in-place access. Cold and warm launches use a queue until Blender/GHOST is ready. |
| **Save As**, or first Save | Uses UIKit's move/export picker with a temporary cache seed. Blender then writes the real project to the returned document path. The seed is not a saved `.blend` project. |
| **Save** after a path is established | Blender writes the current project path without requesting another picker, subject to actual write access. |

PR #4 addresses a specific duplicated-path cause: the old folder-save callback appended a filename to an export result that already contained it, producing paths such as `Untitled.blend/Untitled.blend`. The corrected path handling and provider write access need confirmation on build #81. The broader repeated-nesting report should remain open until reproduced and retested.

The patches retain provider security-scoped URLs, route picker results to the originating Blender window, use a normal-level application window, and suspend Blender gestures behind native modal UI. Picker/handoff diagnostics go to **`Documents/BlenderFiles.log`**. The [native Open/Save audit](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/.github/IOS_SAVE_AUDIT.md) contains the detailed implementation and provider test matrix; its earlier merge-gate wording is historical, since PR #4 has now merged.

**Unexpected closures remain unresolved.** Memory pressure and rendering are investigation candidates; no reviewed termination report establishes the cause of the ongoing closures. Comprehensive memory/render telemetry and a validated recovery workflow remain priorities.

Before treating a build as a daily-use baseline, record its run number and signing route, then verify:

1. Launch, touch alignment, keyboard/mouse/Pencil input, and viewport interaction.
2. Save As to one regular `.blend` file; modify and Save; close and reopen it. Repeat across On My iPad, iCloud Drive, and supported providers, including cancellation and denied/offline access.
3. In-app imports and Files-app cold/warm launches, checking that paths stay stable and folders do not nest unexpectedly.
4. Representative EEVEE/Cycles scenes, enabled import/export formats, Python modules, and audio/video operations, recording failures by subsystem.
5. Background/resume, larger scenes, peak memory/thermal behavior, and recovery after an unexpected termination.

For a read-only check in Blender's Python Console:

```python
import bpy, sys
print("Blender:", bpy.app.version_string, "Python:", sys.version)
print("Project:", repr(bpy.data.filepath))
print("Project directory:", bpy.path.abspath("//") if bpy.data.filepath else "Unsaved project")
```

Blender's `//` is relative to an established project path. An untitled session does not establish a project directory, and the process working directory is not a reliable document location.

## Download and install

1. Open [build #81](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/actions/runs/34008472726) and download **`Blender-iPad-M4-5.2-full`** from its artifacts. GitHub may require sign-in.
2. Extract the artifact and use **`Blender-iPad-M4-5.2-Signulous-unsigned.ipa`** for the project's existing Signulous signing/install route.
3. Keep the matching source, feature, and bundle manifests. The separate **`Blender-iPad-M4-5.2-build-diagnostics`** artifact contains logs and configuration evidence.

| IPA | Purpose |
|---|---|
| `Blender-iPad-M4-5.2-Signulous-unsigned.ipa` | Fallback signing profile without the restricted increased-memory entitlement |
| `Blender-iPad-M4-5.2-full-memory-unsigned.ipa` | Same build with an increased-memory entitlement request, requiring a provisioning/signing profile that supports it |

Both packages have ad-hoc handoff signatures and are unprovisioned; an installation service/profile must supply a valid device signature. The full-memory filename does not establish the installed app's memory allowance. See Apple's [increased memory limit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit).

Artifacts are retained for **21 days**. Their run pages remain useful records after downloads expire.

## Building the current branch

The normal workflow is **GitHub Actions → IPA → Signulous → physical iPad testing**. No local Mac is required to use it.

In [GitHub Actions](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/actions/workflows/build-unsigned-ipa.yml), choose **Run workflow** and select **`upgrade/ios-5.2-m4-full`**. That branch's workflow is named **Build full Blender 5.2 iPad M4 IPA**. The default branch still has the historical workflow, so branch selection matters.

| Build input | Pin / requirement |
|---|---|
| Blender iOS source | [`salmazov/blender-ios@2bc556e58e82eb3a801895f2cb1881c0267e5cd5`](https://github.com/salmazov/blender-ios/tree/2bc556e58e82eb3a801895f2cb1881c0267e5cd5) |
| iOS dependency bundle | `393201c7c8525941553f6a96e19b909d6b3bfc4f` |
| macOS host-tool bundle | `a3e20428fb0ab2231903608cdca90301e130dbfc` |
| Host | Apple-silicon `macos-15` runner, **Xcode 26.3**; run #81 records build `17C529` |
| Target | `arm64` / `iphoneos`, deployment target **26.0** |
| Application ID | `com.gorillafkngorgeous.blenderipad52` |

The [workflow](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/.github/workflows/build-unsigned-ipa.yml) is the authoritative recipe. It prepares source and libraries, restores or builds iOS dependencies, configures Blender, builds the **`blender` scheme** so its app-bundling phase runs, verifies linkage, and packages both IPAs. Source preparation alone is not a complete local build recipe. Local reproduction requires an Apple-silicon Mac and the full bootstrap/configuration steps.

The bootstrap replaces the original bundle's Python 3.11 with matching host/target CPython 3.13.13. It uses iOS compiler wrappers and explicit target dependency paths to prevent macOS library contamination. Native Python modules use iOS frameworks and `.fwork`/`.origin` records; the glTF bridge frameworks contain their statically linked codec dependencies.

Packaging checks cover required assets/modules, framework mappings and signatures, Python linkage, resolvable relative library dependencies, architecture/platform checks, unresolved Git LFS pointers, and entitlement separation. These complement physical-device acceptance.

The M4 shader policy uses a **12 GiB physical-memory threshold** to select higher compilation concurrency, leaving a performance core for interaction. Lower-memory devices or serious thermal pressure retain a two-thread limit. It does not yet use the installed process's actual memory allowance for that decision. Measuring this policy under the Signulous profile is part of stability work. The Cycles iOS dispatch cap is retained for GPU watchdog protection.

## Siri, offline assistance, and agent choice

**Product direction:** substantial, context-aware control over Blender by speaking or typing, with useful native on-device operation without internet access and the ability to choose an external agent.

The proposed architecture shares one versioned Blender action layer across three entry points:

| Entry point | Planned integration | Availability boundary |
|---|---|---|
| Siri and Shortcuts | Swift App Intents, App Entities, and App Shortcuts for supported actions and project context | Siri behavior, supported schemas, OS/language/region, and offline invocation require device validation. |
| Assistant inside GhostBlender | Apple's on-device Foundation Models backend with typed Blender tool calls; local text input and on-device speech where available | Requires supported hardware/settings and downloaded model/speech assets. Offline tools and assets must also avoid network dependencies. |
| User-selected agents | MCP and adapters for other compatible clients using the same actions/results | Remote agents/relays require connectivity. Clients must support a compatible transport and authentication method. |

Apple's [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts) expose intents with invocation phrases. Newer natural-language Siri integration uses [App Schemas](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence); the [current domain catalog](https://developer.apple.com/documentation/appintents/app-schema-domains) has no general Blender/3D-modeling domain. Map matching file/search actions to supported schemas and expose other operations through custom intents/shortcuts and the in-app assistant. Arbitrary modeling language requires validation beyond registering an intent.

The [Foundation Models on-device API](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models) and [tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling) provide the basis for the offline assistant. This is a separate integration from the system Siri interface. Select the on-device backend explicitly, check availability, and retain direct controls when unavailable. The current Xcode 26.3 build can target the original iPadOS 26 APIs; adopting iPadOS 27-only APIs requires a separate toolchain update and availability checks.

Blender should supply exact scene data and execute operations. The model interprets intent and selects tools; it should not have to invent Blender code or estimate geometry to complete ordinary commands.

### Planned action coverage

| Area | Work the assistant should be able to perform |
|---|---|
| Scene understanding | Inspect selection, objects, collections, hierarchy, materials, cameras, active mode, and render state; resolve “this object” from actual context. |
| Modeling | Create/arrange geometry, edit transforms, duplicate/align, apply modifiers, manage selection, and build reusable Geometry Nodes workflows. |
| Materials and lighting | Create/edit materials and nodes, assign textures, adjust lights, and prepare a requested look. |
| Animation | Set keyframes, inspect rigs/actions, adjust timing, and construct repeatable animation operations. |
| Rendering and delivery | Configure EEVEE/Cycles, frame cameras, start/cancel jobs, inspect outputs, import/export, and save through the document layer. |
| Project assistance | Explain controls, identify missing assets, report measured resource use, keep checkpoints, and undo supported edits. |

Build the catalog from Blender's Python/RNA/operator interfaces where practical, with context requirements and capability checks. Expand systematic coverage beyond the prototype's initial tools. Versioned requests/results should carry object identifiers, validated parameters, actual results/errors, and job state. Run Blender data access and mutations on its main thread through a controlled bridge from Swift or the network layer. Start with foreground operation, bounded queues, and explicit unavailable/disconnected results when Blender cannot service work. Undo, checkpoints, cancellation, and post-action inspection support longer sequences; irreversible file operations need their own handling.

Users should be able to choose and disconnect agents, scope scene/file access, decide what leaves the device, and see what changed. Local assistance must remain independent of an external provider account. A cloud fallback should be an explicit choice.

### Existing MCP prototype

[PR #3](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/pull/3) contains a Node MCP service, a Blender Python startup panel, Cloud Run deployment scripting, and transport tests. Its agent-facing endpoint uses [MCP Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports); the iPad makes a separate authenticated outbound HTTPS polling connection. Network work is queued for a Blender timer to execute on the main thread.

Its seven tools are `get_bridge_status`, `get_scene_summary`, `list_objects`, `run_capability_tests`, `create_primitive`, `set_object_transform`, and `save_blend_file`. The save tool creates new files inside app Documents. The prototype exposes named operations and does not provide arbitrary Python execution.

This starting implementation is **not included in 5.2**, and deployment/device validation are unconfirmed. The PR lists deployment, connection setup, installation, and physical iPad testing as outstanding. Its temporary capability-URL/device-token authentication and single-instance in-memory broker need further work for multiple users, durable jobs, and broader client support. Port useful code to the 5.2 action/document layer; its older input/build baseline should not replace the current harness. See the [prototype README](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/feature/ipad-mcp-bridge/mcp-server/README.md).

## Development priorities

1. **Make project work dependable.** Validate build #81's save/open behavior, diagnose termination causes, and establish recovery and memory/render measurements under the installed signing profile.
2. **Establish the common action layer.** Port useful MCP operations to 5.2; add context/capability discovery, identifiers, results, undo/checkpoints, and cancellation. Verify the same operations through each adapter.
3. **Deliver an offline assistant milestone.** Add the Swift bridge and on-device model; demonstrate a local editing sequence and result inspection with networking disabled. Measure additional memory and latency alongside Blender.
4. **Integrate Siri deeply.** Expose project entities and actions through App Intents/Shortcuts and matching schemas. Test actual invocation, foreground handoff, context resolution, and offline behavior on supported OS versions.
5. **Open agent choice and expand coverage.** Validate multiple clients, reconnect/retry behavior, permissions, and longer creative workflows. Track supported operations against the catalog rather than treating a small tool list as the final product.

## Repository guide and contributions

These links target the **5.2 branch**, including when reading this overview on `main`.

| Location | Responsibility |
|---|---|
| [Build workflow](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/.github/workflows/build-unsigned-ipa.yml) | Bootstrap, configure, compile, package, and upload |
| [`scripts/prepare-source.sh`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/scripts/prepare-source.sh) | Source/library pins and ordered transforms |
| [`patches/`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/tree/upgrade/ios-5.2-m4-full/patches) | Blender/iOS, geometry, Files, linkage, codec, and NumPy changes |
| [`scripts/apply-ios-files-scene.py`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/scripts/apply-ios-files-scene.py) | Final native picker and scene handoff transformations |
| [`scripts/verify-app-linkage.sh`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/scripts/verify-app-linkage.sh) | Embedded Python and relative dependency checks; bundle manifest |
| [`scripts/package-ipa.sh`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/scripts/package-ipa.sh) | Bundle validation, mappings, signatures, and IPA profiles |
| [`scripts/write-feature-manifest.sh`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/scripts/write-feature-manifest.sh) | Required feature gates and complete feature manifest |
| [Files regression checks](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/blob/upgrade/ios-5.2-m4-full/tests/test_ios_native_save_transform.py) | Seven source-text checks for native Files transforms |

Keep feature removals explicit and evidence-based. Preserve the host/iOS dependency boundary, package the complete app, and associate device reports with an exact build and signing route. The seven Files checks passed during this audit; they inspect source text and do not exercise UIKit or Files providers. Run them with `python3 -m unittest discover -s tests -v` from the 5.2 checkout.

Blender and its upstream iOS contributors provide the foundation for this project; the current pin comes from [Sergei Almazov's iOS fork](https://github.com/salmazov/blender-ios). Blender is GPL-licensed. Preserve corresponding source, modifications, build information, and applicable dependency notices when distributing modified builds; see [Blender's licensing information](https://www.blender.org/about/license/).
