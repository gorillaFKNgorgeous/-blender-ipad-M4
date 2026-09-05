# iPad native Open and Save audit

## Build 77 findings and traced call paths

Blender's ordinary **Save** does not request a picker once `Main.filepath` is established; it writes the
current filepath. **Save As**, and **Save** for an untitled project, request a native GHOST save dialog.
GHOST returns either one filesystem path or a null cancellation through
`GHOST_kEventNativeFileDialogResult`; Blender's existing continuation writes the `.blend` and adopts the
returned path. This is the path that becomes `bpy.data.filepath`, defines `//`, and is reused by the next
ordinary Save.

The build pipeline applies `ios-native-files.patch`, `ios-files-lifecycle-v2.patch`, and then
`apply-ios-files-scene.py`. The transform is authoritative for the final picker modes. It deliberately
does not alter the working `UISceneDelegate`, URL queue, scene URL handling, retained Metal window, or
`LSSupportsOpeningDocumentsInPlace` configuration.

### Save As root cause

Build 77 correctly replaced the old `UTTypeFolder` opening picker with an export picker, but passed
`asCopy:YES`. That requests an export copy, and the returned URL observed on device did not grant the
write scope Blender needed. Save As now uses `initForExportingURLs:asCopy:NO`: Files performs a move
transaction for the disposable cache seed and returns the selected document URL for continued access.
The provider-returned URL is retained before GHOST delivers its exact filesystem representation.

The duplicated `Untitled.blend/Untitled.blend` was independent of the copy flag. The legacy folder-save
delegate still had `defaultFilename` populated by its filename alert. It treated the export callback URL
(`/.../Untitled.blend`) as the old directory selection and appended `Untitled.blend` again. Filename
appending is now explicitly restricted to `UIDocumentPickerModeOpen`; an export/move result is already a
complete document URL and is passed through unchanged.

UIKit's export initializer requires an existing representation. GHOST creates an empty, uniquely scoped
cache seed with the proposed filename. It is solely input to the Apple transaction, not the project or
an Inbox working copy. Its private parent directory is cleaned after success or cancellation. The real
project is written by Blender at the returned URL.

### Open root cause and strategy

Build 77 forced `initForOpeningContentTypes:asCopy:NO`. On the tested picker/provider combination Files
displayed the browser but did not permit selection and never called the delegate, even with the repaired
scene lifecycle. This establishes a provider/picker interoperability failure rather than a lost GHOST
callback: no callback existed to route.

`File -> Open` now requests UIKit import mode (`asCopy:YES`), which is the mode verified to return a
selection. The delegate immediately copies that temporary result exactly once to the intentional,
writable `Documents/Blender/Imports` directory and hands only that stable path to Blender. A collision
gets a UUID suffix rather than overwriting an existing import. Blender never operates from
`...-Inbox`. True provider open-in-place is still supported for Files-app document launches through the
unchanged `scene:openURLContexts:` path; those URLs are retained and handed to Blender without copying.

Relevant Apple APIs:

* [`initForOpeningContentTypes:asCopy:`](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/initforopeningcontenttypes:ascopy:)
* [`initForExportingURLs:asCopy:`](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/initforexportingurls:ascopy:)
* [Accessing documents](https://developer.apple.com/documentation/uikit/view-controllers/providing-access-to-directories)

## Security scope and error behavior

Provider URLs are retained as `NSURL` objects; they are not reconstructed from sandbox-dependent path
strings. The existing iOS file bridge looks up the retained URL and balances
`startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource` around Blender's actual
file I/O. The diagnostic probe is independently balanced. Controlled imports are app-container files
and require no security scope. Setup/copy failures are logged and return cancellation rather than an
invalid path; save write failures remain normal Blender operator errors instead of being reported as
success by UIKit.

A third-party provider can still be offline, delay materialization, reject a move, or fail to restore
access after relaunch. UIKit cannot guarantee provider availability. Each supported provider therefore
requires the device matrix below. Persistent security-scoped bookmarks may warrant separate future work
if a provider does not restore scope via a subsequent Files-app launch.

## Exact device test procedure

1. Install the corrected unsigned IPA after signing, launch Blender, and retain
   `Documents/BlenderFiles.log` for the run.
2. Choose **File -> New -> General**, change the default cube, then choose **File -> Save As**.
3. Verify Files presents save/export UI. Choose a folder, name the file `Project.blend`, and confirm.
4. Verify the saved item is one regular file at `/chosen/folder/Project.blend`, never
   `Project.blend/Project.blend`.
5. In Blender's Python Console run `bpy.data.filepath` and confirm it is the exact selected document.
   Run `bpy.path.abspath("//")` and confirm it is `/chosen/folder/`.
6. Modify the scene and choose **File -> Save**. Confirm no picker appears and the same file changes.
7. Close Blender. In Files, use **Open in Blender** on `Project.blend`; modify the scene and Save. Confirm
   the provider document changes and no Inbox working file is created.
8. In Blender choose **File -> Open**, select another `.blend`, and confirm it opens from
   `Documents/Blender/Imports`, not `/tmp/...-Inbox`. Open it again and confirm the collision-safe import
   does not replace the first copy.
9. Start Save As again and cancel. Confirm `bpy.data.filepath` is unchanged. Repeat toward an existing
   filename and proceed only through Files' intentional replacement UI.
10. Repeat steps 2-9 for On My iPad, iCloud Drive, and every supported third-party provider. Include an
    offline/denied operation and verify Blender reports an error.
11. Inspect `BlenderFiles.log` for exact Open/Save mode, `asCopy`, allowed content types, seed and callback
    URLs, scope-start result, sandbox/provider classification, controlled-import decision, final path,
    cancellation/failure, presentation mode, and cleanup result.

## Follow-up observations

* Linux tests validate transformation contracts but cannot execute File Provider extensions or compile
  Objective-C++ against the iPadOS SDK. Do not merge until the corrected workflow is built and the
  complete device matrix above passes.
* A future upstream bridge could log Blender's post-callback write return value directly. At present
  UIKit/GHOST log transaction and path delivery, while Blender's save operator owns and displays the
  authoritative write success/failure.
* Migrating to a `UIDocumentBrowserViewController` root is not part of this fix; it would require a broad
  redesign around Blender's Metal window and scene lifecycle.

## Naming and convention notes

No `AGENTS.md` or repository naming-convention document was present. New Objective-C constants use named
`k`-prefixed identifiers and helpers use lower camel case. Apple selector spelling and Blender/GHOST API
names remain exact even if a future local naming convention differs.
