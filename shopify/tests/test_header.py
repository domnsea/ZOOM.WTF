import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APPLY = ROOT / "shopify" / "apply_header.py"
APPLY_SITE = ROOT / "shopify" / "apply_site.py"
PATCH = ROOT / "shopify" / "theme-patch"

NAV = """
<nav class="nav nav--classic">
  <div class="ballroom-header-lockup" data-logo-rev="neon-fingerprint">
    <a class="ballroom-header-logo-link" href="/">
      <img
        class="ballroom-header-logo-img"
        src="{{ 'ballroom-header-logo.png' | asset_url }}"
        alt="Ballroom.WTF"
      >
    </a>
  </div>
  <div class="nav-links-desktop-flow__primary">
    <div class="nav-mnav-item nav-mnav-item--leaf"><a
  class="nav-link nav-link--classic nav-mnav-leaf-link nav-link--zoom-wtf nav-link--brand-lime"
  href="/pages/zoom-wtf"
>
  1132.WTF
</a>
</div>
  </div>
  <div class="nav-mobile-quick__grid">
    <a class="nav-mobile-quick__btn nav-link--brand-lime" href="/pages/zoom-wtf">1132.WTF</a>
  </div>
  <div id="mnav-panel-main-hub">
    <a class="nav-link nav-link--classic nav-link--mnav-sub nav-link--zoom-wtf" href="/pages/zoom-wtf">1132.WTF</a>
  </div>
</nav>
<style>
  :root { --nav-height: 68px; --below-fixed: var(--nav-measured-height, var(--nav-height)); }
  .home-hero-product { padding-top: var(--below-fixed, 72px) !important; }
</style>
"""


class HeaderChromeTest(unittest.TestCase):
    def test_snippet_uses_video_logo_and_white_directory(self):
        chrome = (PATCH / "snippets" / "site-header-chrome.liquid").read_text()
        logo = (PATCH / "snippets" / "ballroom-header-logo.liquid").read_text()
        self.assertIn("ballroom-header-logo.mp4", chrome)
        self.assertIn("ballroom-header-logo.mp4", logo)
        self.assertIn("ZOOM DIRECTORY", chrome)
        self.assertIn("#ffffff", chrome)
        self.assertIn("--below-fixed", chrome)
        self.assertIn("syncSitewideNavOffset", chrome)
        self.assertIn("playsinline", logo)
        self.assertTrue((PATCH / "assets" / "ballroom-header-logo.mp4").is_file())

    def test_apply_header_copies_assets_and_patches_nav(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "layout").mkdir()
            (root / "layout" / "theme.liquid").write_text("<html><body>\n" + NAV + "\n</body></html>\n")
            proc = subprocess.run(
                [sys.executable, str(APPLY), str(root)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("Copied", proc.stdout)
            self.assertTrue((root / "assets" / "ballroom-header-logo.mp4").is_file())
            self.assertTrue((root / "snippets" / "site-header-chrome.liquid").is_file())
            layout = (root / "layout" / "theme.liquid").read_text()
            self.assertIn("{% render 'site-header-chrome' %}", layout)
            self.assertIn("ballroom-header-logo-video", layout)
            self.assertIn("ZOOM DIRECTORY", layout)
            self.assertIn('href="/pages/zoom-directory"', layout)
            self.assertIn("nav-link--brand-white", layout)
            self.assertIn("--nav-height: 240px;", layout)
            self.assertIn("var(--below-fixed, 240px)", layout)
            self.assertEqual(layout.count("{% render 'site-header-chrome' %}"), 1)
            subprocess.run(
                [sys.executable, str(APPLY), str(root)],
                check=True,
                capture_output=True,
                text=True,
            )
            layout2 = (root / "layout" / "theme.liquid").read_text()
            self.assertEqual(layout2.count("{% render 'site-header-chrome' %}"), 1)
            self.assertEqual(layout2.count("ZOOM DIRECTORY"), layout.count("ZOOM DIRECTORY"))

    def test_apply_site_keeps_five_platforms(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "layout").mkdir()
            (root / "templates").mkdir()
            (root / "layout" / "theme.liquid").write_text(
                "<html><body>\n"
                + NAV
                + """
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
    .zoom-wtf-modal__choice--mac:hover { border-color: #7ec94a; }
    .zoom-wtf-modal__choice--win:hover { border-color: #3d95ce; }
</body></html>
"""
            )
            (root / "templates" / "page.zoom-wtf.liquid").write_text(
                '<p class="zoom-wtf-page__lead">Enter your email, pick <strong>Windows</strong>, <strong>Mac</strong>, or <strong>Linux</strong>, pay $10.00. Shopify emails the correct installer automatically after payment.</p>\n'
                '<p class="home-hero-product__price">Windows · Mac · Linux Zoom workaround</p>\n'
                '      data-linux-vid="52939951964436"\n'
                """        <div class="zoom-wtf-page__choices" aria-label="Choose platform">
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
"""
            )
            proc = subprocess.run(
                [sys.executable, str(APPLY_SITE), str(root)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("Copied", proc.stdout)
            page = (root / "templates" / "page.zoom-wtf.liquid").read_text()
            layout = (root / "layout" / "theme.liquid").read_text()
            for name in ("Mac", "Windows", "Linux", "iOS", "Android"):
                self.assertIn(f'data-zoom-platform="{name}"', page)
                self.assertIn("$10.00 · Auto-email", page)
            self.assertIn("ZOOM DIRECTORY", layout)
            self.assertIn("ballroom-header-logo-video", layout)


if __name__ == "__main__":
    unittest.main()
