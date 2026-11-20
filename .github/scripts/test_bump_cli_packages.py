import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from http.client import IncompleteRead
from pathlib import Path
from unittest import mock
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlsplit


spec = importlib.util.spec_from_file_location("bump_cli_packages", Path(__file__).with_name("bump-cli-packages.py"))
bump = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bump)


class GitHubReleaseTests(unittest.TestCase):
    def test_small_pages_find_complete_stable_release(self):
        complete = {
            "tag_name": "rust-v0.163.0",
            "assets": [
                {"name": "codex-package-x86_64-unknown-linux-musl.tar.gz", "state": "uploaded"},
                {"name": "codex-package-aarch64-unknown-linux-musl.tar.gz", "state": "uploaded"},
                {"name": "codex-package-aarch64-apple-darwin.tar.gz", "state": "uploaded"},
            ],
        }
        pages = [
            [{"tag_name": "rust-v0.164.0-alpha.1", "assets": complete["assets"]}] * 9
            + [{"tag_name": "rust-v0.164.0", "assets": complete["assets"][:1]}],
            [complete],
        ]

        def fetch_page(request, timeout):
            query = parse_qs(urlsplit(request.full_url).query)
            if query.get("per_page") != ["10"]:
                raise HTTPError(request.full_url, 504, "Gateway Timeout", {}, None)
            page = int(query.get("page", ["1"])[0])
            return io.BytesIO(json.dumps(pages[page - 1]).encode())

        with mock.patch.object(bump.urllib.request, "urlopen", side_effect=fetch_page) as urlopen:
            self.assertEqual(bump.latest_github_release(bump.PACKAGES["codex"]), "0.163.0")
        self.assertEqual(urlopen.call_count, 2)

    def test_stops_when_releases_are_exhausted(self):
        for releases in [[], [{"tag_name": "nightly"}]]:
            with self.subTest(releases=releases):
                with mock.patch.object(bump, "fetch_text", return_value=json.dumps(releases)) as fetch_text:
                    with self.assertRaisesRegex(RuntimeError, "could not find a release"):
                        bump.latest_github_release(bump.PACKAGES["codex"])
                self.assertEqual(fetch_text.call_count, 1)

    def test_scans_at_most_100_releases(self):
        with mock.patch.object(
            bump, "fetch_text", return_value=json.dumps([{"tag_name": "nightly"}] * 10)
        ) as fetch_text:
            with self.assertRaisesRegex(RuntimeError, "could not find a release"):
                bump.latest_github_release(bump.PACKAGES["codex"])
        self.assertEqual(fetch_text.call_count, 10)

    def test_skips_unpublished_assets_and_does_not_downgrade(self):
        config = bump.PACKAGES["orcad"]
        assets = [{"name": name, "state": "uploaded"} for name in config["assets"].values()]
        releases = [
            {"tag_name": "v1.4.101", "prerelease": True, "assets": assets},
            {"tag_name": "v1.4.100", "assets": [*assets[:-1], {**assets[-1], "state": "new"}]},
            {"tag_name": "v1.4.99", "assets": assets},
        ]
        with mock.patch.object(bump, "fetch_text", return_value=json.dumps(releases)):
            self.assertEqual(bump.latest_version("orcad", config, "1.4.98"), "1.4.99")
            self.assertEqual(bump.latest_version("orcad", config, "1.4.100"), "1.4.100")


class BatchUpdateTests(unittest.TestCase):
    def test_fetch_and_build_failures_keep_their_pins(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packages = {
                name: {"path": root / f"{name}.nix", "assets": {}} for name in ("unreachable", "broken", "working")
            }
            original = 'version = "1.0.0";\n'
            for config in packages.values():
                config["path"].write_text(original)

            output = root / "output"
            with (
                mock.patch.object(bump, "ROOT", root),
                mock.patch.object(bump, "PACKAGES", packages),
                mock.patch("sys.argv", ["bump-cli-packages.py"]),
                mock.patch.dict("os.environ", GITHUB_OUTPUT=str(output)),
                mock.patch.object(bump, "latest_version", side_effect=[IncompleteRead(b""), "2.0.0", "2.0.0"]),
                mock.patch.object(
                    bump.subprocess, "run", side_effect=[subprocess.CalledProcessError(1, "nix build"), None]
                ) as build,
                mock.patch("sys.stdout", new_callable=io.StringIO),
            ):
                bump.main()

            self.assertEqual([call.args[0][-1] for call in build.call_args_list], [".#broken", ".#working"])
            self.assertEqual(packages["unreachable"]["path"].read_text(), original)
            self.assertEqual(packages["broken"]["path"].read_text(), original)
            self.assertIn('version = "2.0.0";', packages["working"]["path"].read_text())
            self.assertIn("files=working.nix", output.read_text().splitlines())


if __name__ == "__main__":
    unittest.main()
