import importlib.util
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("bump_orcad", Path(__file__).with_name("bump-orcad.py"))
bump = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bump)


class OrcadReleaseTests(unittest.TestCase):
    def setUp(self):
        self.package = bump.VERSION_PIN.sub(r"\g<1>1.4.99\3", bump.PACKAGE.read_text())
        self.release = {
            "tag_name": "v1.4.100",
            "draft": False,
            "prerelease": False,
            "assets": [
                {"name": bump.ASSETS[0], "state": "uploaded", "digest": "sha256:" + "00" * 32},
                {"name": bump.ASSETS[1], "state": "uploaded", "digest": "sha256:" + "ff" * 32},
                {"name": bump.CHECKSUMS, "state": "uploaded"},
            ],
        }

    def test_updates_both_hashes_only_after_assets_are_uploaded(self):
        updated, version = bump.update_pin(self.package, self.release)
        self.assertEqual(version, "1.4.100")
        self.assertIn('version = "1.4.100";', updated)
        self.assertIn('arch = "x64";\n      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";', updated)
        self.assertIn('arch = "arm64";\n      hash = "sha256-//////////////////////////////////////////8=";', updated)

    def test_incomplete_release_leaves_current_pin(self):
        for asset in self.release["assets"]:
            with self.subTest(asset=asset["name"]):
                asset["state"] = "new"
                self.assertEqual(bump.update_pin(self.package, self.release), (self.package, "1.4.99"))
                with self.assertRaisesRegex(ValueError, "missing published server assets"):
                    bump.update_pin(self.package, self.release, "1.4.100")
                asset["state"] = "uploaded"

    def test_never_downgrades_automatically(self):
        self.release["tag_name"] = "v1.4.98"
        self.assertEqual(bump.update_pin(self.package, self.release), (self.package, "1.4.99"))
        self.assertEqual(bump.update_pin(self.package, self.release, "1.4.98")[1], "1.4.98")

    def test_skips_current_version(self):
        self.release["tag_name"] = "v1.4.99"
        self.assertEqual(bump.update_pin(self.package, self.release), (self.package, "1.4.99"))

    def test_rejects_unusable_release(self):
        self.release["prerelease"] = True
        with self.assertRaisesRegex(ValueError, "published stable"):
            bump.update_pin(self.package, self.release)
        self.release["prerelease"] = False
        self.release["assets"][0]["digest"] = None
        with self.assertRaisesRegex(ValueError, "invalid GitHub SHA-256"):
            bump.update_pin(self.package, self.release)


if __name__ == "__main__":
    unittest.main()
