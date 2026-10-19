import importlib.util
import io
import json
import unittest
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
                {"name": "codex-package-x86_64-unknown-linux-musl.tar.gz"},
                {"name": "codex-package-aarch64-unknown-linux-musl.tar.gz"},
                {"name": "codex-package-aarch64-apple-darwin.tar.gz"},
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


if __name__ == "__main__":
    unittest.main()
