# Blender iPad project status

Last audited: **6 September 2026**. The [README](README.md) contains the current project overview, evidence, build instructions, and Siri/agent roadmap. This note replaces the 28 August snapshot that predated the 5.2 work. It records project state; it does not make an untested device feature verified.

## Current baseline and branches

- The active build branch is [`upgrade/ios-5.2-m4-full`](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/tree/upgrade/ios-5.2-m4-full). Blender 5.2 has been built repeatedly, installed, and reported running on the project's iPad Pro M4. Earlier reports include corrected display/touch alignment and working scene loading/file insertion.
- The target device is the 1 TB / 16 GB M4 iPad Pro running iPadOS 27; deployment minimum is iPadOS 26.0.
- `main` still contains the historical 5.0 harness. Updating its documentation does not merge or promote the 5.2 build code. Select the 5.2 branch when starting a current build.
- `upgrade/ios-5.1.2` preserves the earlier running baseline. `fix/ios-desktop-input` and its open PR #1 belong to that older development line; do not apply that patch wholesale over the newer 5.2 iOS input implementation.
- The normal installation workflow remains GitHub Actions → IPA → Signulous → iPad. A local Mac is not a prerequisite for that workflow.

## Latest verified build evidence

[Run #81](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/actions/runs/34008472726) passed on 6 September 2026, completing at 04:10 UTC. It built harness commit `c9b9d486b390333e396ba882b33d9a2b6ae591e1`, after [PR #4](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/pull/4) merged the native Open/Save changes.

Blender source remains pinned at `2bc556e58e82eb3a801895f2cb1881c0267e5cd5`. Run #81's downloaded diagnostics confirm the source revision, all 20 required feature flags enabled, and a bundle with 45 Mach-O binaries including Python, NumPy, Zstandard, and both glTF codec bridge frameworks. The eight patch hashes match the audited checkout. The supplied 5 September manifests are earlier evidence, with harness commit `ecf4b8882de25edc3c7b9b03e5d9df278cb67efd`.

The seven existing Files source-text regression checks passed during the audit. They do not run UIKit or File Provider extensions. Compilation and packaging do not establish signed-device acceptance.

## Open runtime work

The currently installed build number and build #81's device results have not been confirmed in this audit. Keep these items open:

- Save As, subsequent Save, cancellation, replacement, and save/reopen across supported providers.
- Repeated folder/path nesting. PR #4 fixes the specific duplicate-filename export callback; the broader report needs retesting.
- Cold/warm Files launches, controlled picker imports, and stable project-relative paths.
- Unexpected app closures, memory/render measurements, and recovery. Memory pressure/rendering are hypotheses for the ongoing closures, not established causes.
- Representative rendering, imports/exports, Python modules, audio/video, input, and lifecycle tests.

Use `Documents/BlenderFiles.log` for file handoffs. Collect exact run number, IPA/signing route, reproduction steps, and termination diagnostics with device reports. Optimize against the actual installed memory allowance; the full-memory IPA name or physical 16 GB does not establish that allowance.

## Siri and agent direction

The user's vision is deep, actionable Siri integration; a capable native assistant that can work on-device without internet; and the ability to authorize an agent of the user's choosing. The README proposes a common versioned Blender action layer shared by App Intents/Shortcuts, on-device Foundation Models tools, and MCP/other client adapters. None of the Siri/Foundation Models work is implemented in the audited 5.2 harness.

[PR #3](https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/pull/3), branch `feature/ipad-mcp-bridge` at `5eb6ea1d30b68f27aed3c909dcf40eaffde58898`, contains the first MCP relay and Blender startup bridge. It targets `fix/ios-desktop-input`, remains unmerged, and is not in build #81. Deployment, connection setup, and physical iPad validation are listed as outstanding; this audit did not verify a live service.

Next priorities are stable documents/recovery and measured runtime behavior, the shared action layer, offline assistant implementation, Siri integration, and wider agent/creative-operation coverage. Preserve broad Blender capability while addressing documented platform blockers. Separate implemented code, CI evidence, device observations, and future goals whenever updating this note.
