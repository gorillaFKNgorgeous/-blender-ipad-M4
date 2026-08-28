# Blender iPad Project Status

Last updated: 2026-08-28 (Australia/Sydney)

This file is the canonical continuity note for future work on this repository. Read it before proposing build/version changes.

## Current working baseline

- **Current working Blender version on the iPad: Blender 5.1.2.**
- Blender 5.1.2 is already running on the user's **iPad Pro M4**.
- **Blender 5.2 has NOT yet been attempted in this project.** Do not describe prior 5.2 build failures or a prior 5.2 migration.
- The project repository is private: `gorillaFKNgorgeous/-blender-ipad-M4`.
- The current distribution workflow produces an unsigned iOS build/IPA via GitHub Actions, which is then signed/installed using **Signulous**. A local Mac/Xcode build is not the normal project workflow.

## Recent project work

- Keyboard/mouse input repair work reached GitHub Actions workflow #18, attempt 3, commit `682de07`, with the workflow completing successfully.
- File access/open-save permissions and desktop-style input remain important iPad adaptation areas.
- MCP work is being developed separately. GitHub issue #2 preserves the MCP bridge plan.
- MCP draft PR #3 is on branch `feature/ipad-mcp-bridge`, with commit `5eb6ea1`; the intended deployment includes a private remote MCP endpoint / Cloud Run component and does not require an additional PC.

## Blender 5.2 reference port discovered

A highly relevant public reference implementation now exists:

- Repository: `https://github.com/salmazov/blender-ios`
- Branch: `ios-new`
- Author: Sergei Almazov / Reddit user `sergeialmazov`
- Demonstrated Blender 5.2 / 5.2 LTS running on an **iPad Pro M2**.
- Because the user's device is an iPad Pro M4, the M2 demonstration is strong evidence that the core 5.2 iPad port can run on the user's hardware. It is not by itself proof that every feature, dependency, entitlement, or our GitHub/Signulous packaging path will work unchanged.

The reference port includes iPad-specific work that should be studied before we attempt our own Blender 5.2 upgrade, including:

- native iPadOS open/save dialog handling for `.blend` files and rendered images;
- HiDPI/iPad display tuning;
- Apple Pencil event fixes, including Object/Edit mode interaction issues;
- an iOS setup script (`setup_ios.sh`);
- iOS/macOS ARM prebuilt library setup;
- Xcode/CMake configuration for iPadOS;
- reported Cycles and EEVEE rendering on M2 hardware.

## Recommended 5.2 strategy

Do **not** blindly replace the working 5.1.2 codebase.

1. Treat the current 5.1.2 build as the known-good baseline.
2. Inspect/diff `salmazov/blender-ios:ios-new` against Blender upstream and against our current iPad-specific patches.
3. Identify which of Sergei's iPad fixes supersede, complement, or conflict with our keyboard/mouse, file-access, build, and signing changes.
4. Adapt the useful 5.2 changes to our **GitHub Actions -> unsigned IPA -> Signulous** workflow rather than assuming his local Xcode installation process is suitable for us.
5. Build 5.2 on a separate branch/workflow first. Preserve 5.1.2 until 5.2 is installed and validated on the M4 iPad.
6. Validate at minimum: launch, touch, Apple Pencil, external keyboard, left/right mouse click, viewport navigation, file open/save, `.blend` persistence, import/export, EEVEE, Cycles where enabled, and memory/Jetsam stability.

## Continuity rule

Before answering questions about the project's current Blender version, upgrade history, or next build target, use this file as the source of truth and update it whenever a milestone changes.
