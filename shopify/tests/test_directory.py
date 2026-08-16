import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APPLY = ROOT / "shopify" / "apply_directory.py"
PATCH = ROOT / "shopify" / "theme-patch"


class DirectoryThemeTest(unittest.TestCase):
    def test_snippet_refreshes_every_five_minutes(self):
        snippet = (PATCH / "snippets" / "zoom-directory.liquid").read_text()
        self.assertIn("5 * 60 * 1000", snippet)
        self.assertIn("zoom-directory.json", snippet)
        self.assertIn("HOSTBOT2", snippet)
        self.assertIn("name_as_website", snippet)
        self.assertIn("cache: 'no-store'", snippet)
        self.assertIn("/pages/zoom-directory", snippet)
        self.assertIn("2060220206", snippet)
        self.assertIn("973", snippet)
        self.assertIn("raw.githubusercontent.com", snippet)
        self.assertIn("ROOMS.txt", snippet)
        self.assertIn("needs_name", snippet)

    def test_apply_copies_files_and_injects_render(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "layout").mkdir()
            (root / "layout" / "theme.liquid").write_text("<html><body>hello</body></html>\n")
            proc = subprocess.run(
                [sys.executable, str(APPLY), str(root)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("Copied", proc.stdout)
            self.assertTrue((root / "snippets" / "zoom-directory.liquid").is_file())
            self.assertTrue((root / "templates" / "page.zoom-directory.liquid").is_file())
            self.assertTrue((root / "assets" / "zoom-directory.json").is_file())
            self.assertTrue((root / "assets" / "ROOMS.txt").is_file())
            layout = (root / "layout" / "theme.liquid").read_text()
            self.assertIn("{% render 'zoom-directory' %}", layout)
            self.assertIn("</body>", layout)
            proc2 = subprocess.run(
                [sys.executable, str(APPLY), str(root)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(layout.count("{% render 'zoom-directory' %}"), 1)
            self.assertIn("already renders", proc2.stdout)


if __name__ == "__main__":
    unittest.main()
