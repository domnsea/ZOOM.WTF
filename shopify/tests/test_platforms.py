import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APPLY = ROOT / "shopify" / "apply_five_platforms.py"
PATCH = ROOT / "shopify" / "theme-patch"
PLATFORMS = ("Mac", "Windows", "Linux", "iOS", "Android")
VIDS = {
    "Mac": "52818503008532",
    "Windows": "52818503139604",
    "Linux": "52939951964436",
    "iOS": "53566816846100",
    "Android": "53656022221076",
}

FIXTURE_PAGE = """
<p class="zoom-wtf-page__lead">Enter your email, pick <strong>Windows</strong>, <strong>Mac</strong>, or <strong>Linux</strong>, pay $10.00. Shopify emails the correct installer automatically after payment.</p>
<p class="zoom-wtf-page__hint">After you pay, the Windows, Mac, or Linux zip is sent automatically to this email. Use the same address at checkout.</p>
      data-linux-vid="52939951964436"
        <div class="zoom-wtf-page__choices" aria-label="Choose platform">
          <button type="submit" class="zoom-wtf-page__choice" data-zoom-platform="Windows" data-zoom-vid="52818503139604">
            <span class="zoom-wtf-page__choice-label">Windows</span>
            <span class="zoom-wtf-page__choice-sub">$10.00 · Auto-email</span>
          </button>
          <button type="submit" class="zoom-wtf-page__choice" data-zoom-platform="Mac" data-zoom-vid="52818503008532">
            <span class="zoom-wtf-page__choice-label">Mac</span>
            <span class="zoom-wtf-page__choice-sub">$10.00 · Auto-email</span>
          </button>
          <button type="submit" class="zoom-wtf-page__choice" data-zoom-platform="Linux" data-zoom-vid="52939951964436">
            <span class="zoom-wtf-page__choice-label">Linux</span>
            <span class="zoom-wtf-page__choice-sub">$10.00 · Auto-email</span>
          </button>
        </div>
.zoom-wtf-page__choices { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin-top: 8px; }
<p class="home-hero-product__price">Windows · Mac · Linux Zoom workaround</p>
"""

FIXTURE_MODAL = """
    <p class="zoom-wtf-modal__lead">Enter email, pick Windows, Mac, or Linux, pay. The correct installer is emailed automatically after payment.</p>
      <div class="zoom-wtf-modal__choices" aria-label="Choose platform">
        <button type="submit" class="zoom-wtf-modal__choice" data-zoom-platform="Windows" data-zoom-vid="52818503139604">
          <span class="zoom-wtf-modal__choice-label">Windows</span>
          <span class="zoom-wtf-modal__choice-sub">$10.00 · Auto-email</span>
        </button>
        <button type="submit" class="zoom-wtf-modal__choice" data-zoom-platform="Mac" data-zoom-vid="52818503008532">
          <span class="zoom-wtf-modal__choice-label">Mac</span>
          <span class="zoom-wtf-modal__choice-sub">$10.00 · Auto-email</span>
        </button>
        <button type="submit" class="zoom-wtf-modal__choice" data-zoom-platform="Linux" data-zoom-vid="52939951964436">
          <span class="zoom-wtf-modal__choice-label">Linux</span>
          <span class="zoom-wtf-modal__choice-sub">$10.00 · Auto-email</span>
        </button>
      </div>
.zoom-wtf-modal__choices { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
    .zoom-wtf-modal__choice--mac:hover { border-color: #7ec94a; }
    .zoom-wtf-modal__choice--win:hover { border-color: #3d95ce; }
"""


class FivePlatformsTest(unittest.TestCase):
    def test_theme_patch_lists_every_platform_at_ten_dollars(self):
        blob = "\n".join(path.read_text() for path in PATCH.rglob("*.liquid"))
        for name, vid in VIDS.items():
            self.assertIn(f'data-zoom-platform="{name}"', blob)
            self.assertIn(vid, blob)
        self.assertIn("Auto-email", blob)
        self.assertIn("zoom_wtf_price_money", blob)

    def test_apply_script_patches_exported_theme_markup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "templates").mkdir()
            (root / "layout").mkdir()
            (root / "templates" / "page.zoom-wtf.liquid").write_text(FIXTURE_PAGE)
            (root / "layout" / "theme.liquid").write_text(FIXTURE_MODAL)
            proc = subprocess.run(
                [sys.executable, str(APPLY), str(root)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("Updated 2 file(s)", proc.stdout)
            page = (root / "templates" / "page.zoom-wtf.liquid").read_text()
            modal = (root / "layout" / "theme.liquid").read_text()
            for blob in (page, modal):
                for name, vid in VIDS.items():
                    self.assertIn(f'data-zoom-platform="{name}"', blob)
                    self.assertIn(vid, blob)
                    self.assertIn("$10.00 · Auto-email", blob)
            self.assertIn("Mac · Windows · Linux · iOS · Android", page)
            self.assertNotIn("Windows · Mac · Linux Zoom workaround", page)
            self.assertIn("iOS", modal)
            self.assertIn("Android", modal)
            self.assertIn("repeat(auto-fit", page)
            self.assertIn("repeat(auto-fit", modal)

    def test_dist_packages_exist(self):
        dist = ROOT / "dist"
        for name in (
            "1132-FRESH-macos.zip",
            "1132.WTF-windows-1.0.0.zip",
            "1132.WTF-linux-1.0.0.zip",
            "1132.WTF-ios-1.0.0.zip",
            "1132.WTF-android-1.0.0.zip",
        ):
            self.assertTrue((dist / name).is_file(), name)


if __name__ == "__main__":
    unittest.main()
