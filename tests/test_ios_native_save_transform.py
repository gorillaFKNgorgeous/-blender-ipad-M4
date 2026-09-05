from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TRANSFORM = ROOT / "scripts" / "apply-ios-files-scene.py"
PREPARE = ROOT / "scripts" / "prepare-source.sh"


class NativeDocumentPickerTransformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.transform = TRANSFORM.read_text(encoding="utf-8")
        cls.prepare = PREPARE.read_text(encoding="utf-8")

    def test_open_uses_controlled_import(self):
        self.assertIn("initForOpeningContentTypes:contentTypes", self.transform)
        self.assertIn("asCopy:YES", self.transform)
        self.assertIn("controlledImportURL", self.transform)
        self.assertIn("Documents/Blender/Imports", self.transform)
        self.assertIn("controlled-import=yes final-path=%@", self.transform)

    def test_save_uses_writable_move_export(self):
        self.assertIn("initForExportingURLs:@[ saveExportURL ]", self.transform)
        save_replacement = self.transform.split('"Apple-native save export picker"', 1)[0]
        save_replacement = save_replacement.rsplit('""",\n        """', 1)[1]
        self.assertNotIn("UTTypeFolder", save_replacement)
        self.assertIn("asCopy:NO", save_replacement)

    def test_export_callback_cannot_duplicate_filename(self):
        self.assertIn(
            "controller.documentPickerMode == UIDocumentPickerModeOpen",
            self.transform,
        )
        self.assertIn("save export picker presentation completed", self.transform)

    def test_seed_and_import_paths_use_named_constants(self):
        for constant in (
            "kBlenderSaveExportDirectory",
            "kBlenderFallbackSaveFilename",
            "kBlenderDocumentsDirectory",
            "kBlenderImportsDirectory",
        ):
            with self.subTest(constant=constant):
                self.assertIn(constant, self.transform)
        self.assertIn("removeItemAtURL:_saveExportURL.URLByDeletingLastPathComponent", self.transform)

    def test_security_scope_probe_is_balanced(self):
        generated = self.transform.split('"native save export helpers"', 1)[0]
        generated = generated.rsplit('"""', 2)[1]
        self.assertEqual(
            generated.count("startAccessingSecurityScopedResource"),
            generated.count("stopAccessingSecurityScopedResource"),
        )

    def test_build_guards_assert_each_initializer(self):
        self.assertIn("source.count(open_initializer) == 1", self.prepare)
        self.assertIn("source.count(save_initializer) == 1", self.prepare)
        self.assertNotIn("grep -Fq 'asCopy:NO'", self.prepare)

    def test_required_diagnostics_are_present(self):
        for diagnostic in (
            "open picker requested",
            "content-types=%@",
            "open callback received",
            "security-scope-start=%@",
            "controlled-import=yes",
            "save picker requested",
            "picker=move-export",
            "seed=%@",
            "destination=%@",
            "security-scoped=%@",
            "final-save-path=%@",
            "cancelled",
            "failed",
            "cleanup failed",
        ):
            with self.subTest(diagnostic=diagnostic):
                self.assertIn(diagnostic, self.transform)


if __name__ == "__main__":
    unittest.main()
