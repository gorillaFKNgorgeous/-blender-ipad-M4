from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TRANSFORM = ROOT / "scripts" / "apply-ios-files-scene.py"
PREPARE = ROOT / "scripts" / "prepare-source.sh"


class NativeSaveTransformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.transform = TRANSFORM.read_text(encoding="utf-8")
        cls.prepare = PREPARE.read_text(encoding="utf-8")

    def test_open_remains_in_place(self):
        self.assertIn("initForOpeningContentTypes:contentTypes", self.transform)
        self.assertIn("asCopy:NO", self.transform)
        self.assertNotIn("native Files open picker copy mode", self.transform)

    def test_save_uses_export_not_folder_open(self):
        self.assertIn("initForExportingURLs:@[ saveExportURL ]", self.transform)
        replacement = self.transform.split('"Apple-native save export picker"', 1)[0]
        replacement = replacement.rsplit('""",\n        """', 1)[1]
        self.assertNotIn("UTTypeFolder", replacement)
        self.assertIn("asCopy:YES", replacement)

    def test_export_seed_has_named_constants_and_cleanup(self):
        self.assertIn("kBlenderSaveExportDirectory", self.transform)
        self.assertIn("kBlenderFallbackSaveFilename", self.transform)
        self.assertIn("removeItemAtURL:_saveExportURL.URLByDeletingLastPathComponent", self.transform)

    def test_build_guard_rejects_regression(self):
        self.assertIn("Save still uses an open/select folder picker.", self.prepare)
        self.assertIn("initForExportingURLs:@[ saveExportURL ]", self.prepare)

    def test_required_save_diagnostics_are_present(self):
        for diagnostic in (
            "save picker requested",
            "operation=Save As",
            "picker=export",
            "destination=%@",
            "security-scoped=%@",
            "external-provider",
            "callback delivered",
            "final-save-path=%@",
            "cancelled",
            "failed",
        ):
            with self.subTest(diagnostic=diagnostic):
                self.assertIn(diagnostic, self.transform)


if __name__ == "__main__":
    unittest.main()
