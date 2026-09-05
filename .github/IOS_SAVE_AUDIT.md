# iPad native Save audit and follow-up notes

## Scope and traced call path

Blender's desktop operators retain their normal semantics. An ordinary **Save** with an established
`Main.filepath` writes that path directly. **Save As**, and **Save** for an untitled project, request a
native GHOST save dialog. GHOST returns either a filesystem path or a null cancellation through
`GHOST_kEventNativeFileDialogResult`; Blender's existing file-browser continuation performs the actual
`.blend` write and adopts that returned path. Consequently `bpy.data.filepath`, `//` resolution, and a
later ordinary Save all follow Blender's existing behavior rather than being reimplemented in UIKit.

The iOS pipeline applies `ios-native-files.patch`, then `ios-files-lifecycle-v2.patch`, and finally
`apply-ios-files-scene.py`. The last transform is therefore the authoritative picker configuration.
The previous version changed Open to copy mode and left save configured as an opening picker restricted
to `UTTypeFolder`. That API necessarily displayed an **Open** action and returned a directory. Appending
a filename did not turn the selection transaction into a save/export transaction.

## Apple API decision

The modern UIKit operations are deliberately separate:

* [`initForOpeningContentTypes:asCopy:`](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/initforopeningcontenttypes:ascopy:)
  is retained with `asCopy:NO` for opening provider documents in place.
* [`initForExportingURLs:asCopy:`](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/initforexportingurls:ascopy:)
  is used for Save As. Files owns the destination, filename, and intentional conflict/replacement UI.
* Apple's [document-based app overview](https://developer.apple.com/documentation/uikit/documents-data-and-pasteboard/building-a-document-browser-based-app)
  is a possible longer-term architecture, but adopting a `UIDocumentBrowserViewController` root would
  conflict with Blender's retained Metal window and is intentionally outside this narrow repair.

UIKit's export initializer requires an existing local representation. GHOST creates an empty,
uniquely-scoped cache representation carrying Blender's proposed filename, presents it to the export
picker, and removes it on success or cancellation. This is not an Inbox/import copy or the saved
project: it is the seed required by the Apple export transaction. Blender writes the real document to
the provider-returned destination URL, which remains the authoritative project location.

## Security scope and provider behavior

The provider-issued destination URL is stored without reconstructing it from its path. The existing
GHOST iOS I/O bridge looks up the retained URL and balances
`startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource` around file access. The
picker delegate does not leak a permanently open scope. Sandbox destinations are identified only for
diagnostics; no sandbox UUID is hard-coded.

Third-party providers may be offline, may take time to materialize an export, or may decline subsequent
write access. UIKit can grant access but cannot guarantee provider availability. Blender's normal save
operator must surface such an I/O failure; the log records picker/setup/callback failures and the final
path handoff. Device validation should confirm the exact provider's replacement UI and durable
subsequent access.

## Exact device test procedure

1. Install a newly built IPA and open `Documents/BlenderFiles.log` through Files sharing.
2. Start **File → New → General**, make an obvious scene edit, then choose **File → Save As**.
3. Confirm Files shows an export/save destination workflow (not a folder **Open** picker), keep the
   `.blend` extension visible, choose both a destination and filename, and confirm.
4. In Blender's Python Console verify `bpy.data.filepath` is the chosen document path. Create a relative
   reference and verify `bpy.path.abspath("//")` resolves to its containing Files directory.
5. Modify the scene and choose **File → Save**. Confirm no picker appears and the same document's
   modification date/content changes.
6. Close Blender, reopen that exact document from Files, modify it, and choose **File → Save** again.
   Confirm no Inbox copy appears and the original document changes.
7. Repeat Save As to an existing filename. Replace only after the Files UI explicitly asks/allows it;
   cancel once and verify `bpy.data.filepath` remains unchanged.
8. Repeat with iCloud Drive and each supported third-party provider, including an offline/failure case.
   Confirm Blender reports failure rather than silently returning and inspect `BlenderFiles.log` for
   request type, picker mode, destination, scope/location classification, callback, final path, and
   cancellation/failure entries.

## Items warranting closer review

* Add an on-device UI/integration test harness when Apple-silicon runners can host the target iPadOS
  runtime; Linux CI can validate transforms but cannot exercise Files-provider extensions.
* Consider security-scoped bookmarks for persistence across a full app relaunch if a provider does not
  restore access through the Files open-in-place launch. Do not substitute hard-coded container paths.
* Correlate Blender's post-callback write completion with `BlenderFiles.log` in a future upstream change;
  today final write errors remain Blender operator reports, while GHOST logs native transaction setup
  and path delivery.
* Keep the current scene delegate, URL queue, Metal window retention, and
  `LSSupportsOpeningDocumentsInPlace`; a future document-browser-root migration would require a broader
  lifecycle design and should not be mixed into picker repairs.

## Naming/style notes

No repository naming convention file was present. New Objective-C constants use the established `k`
prefix and helper functions use lower camel case. The UIKit selector spellings and Blender/GHOST names
are platform/upstream API names and must remain exact even if a future local convention differs.
