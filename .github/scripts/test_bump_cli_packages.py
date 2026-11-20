import importlib.util
import io
import json
import os
import subprocess
import tempfile
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

    def test_orcad_waits_for_the_complete_stable_release(self):
        config = bump.PACKAGES["orcad"]
        release = {
            "tag_name": "v1.4.100",
            "draft": False,
            "prerelease": False,
            "assets": [
                {"name": name, "state": "uploaded"}
                for name in (*config["assets"].values(), "orca-server-sha256sums.txt")
            ],
        }
        with mock.patch.object(bump, "fetch_text", side_effect=lambda *args, **kwargs: json.dumps(release)):
            self.assertEqual(bump.orcad_version(config, "1.4.99", ""), "1.4.100")
            self.assertEqual(bump.orcad_version(config, "1.4.101", ""), "1.4.101")
            release["assets"][1]["state"] = "new"
            self.assertEqual(bump.orcad_version(config, "1.4.99", ""), "1.4.99")
            with self.assertRaisesRegex(ValueError, "missing published server assets"):
                bump.orcad_version(config, "1.4.99", "1.4.100")


@unittest.skipUnless(os.environ.get("ORCAD_PACKAGE"), "requires a built Orcad package")
class OrcadRuntimeTests(unittest.TestCase):
    def test_server_starts_and_pairs(self):
        package = Path(os.environ["ORCAD_PACKAGE"])
        cli = package / "bin/orca-ide"
        with tempfile.TemporaryDirectory(prefix="orcad-smoke-") as root:
            server_env = {**os.environ, "ORCA_USER_DATA_PATH": f"{root}/server", "ORCA_TELEMETRY_DISABLED": "1"}
            client_env = {**server_env, "ORCA_USER_DATA_PATH": f"{root}/client"}
            version = subprocess.check_output([cli, "--version"], env=client_env, text=True, timeout=15).strip()
            self.assertEqual(version, bump.current_version(bump.PACKAGES["orcad"]["path"]))
            with subprocess.Popen(
                [package / "bin/orcad", "--port", "0", "--json"],
                env=server_env,
                stdout=subprocess.PIPE,
                text=True,
            ) as server:
                try:
                    line = next(
                        (line for line in server.stdout if line.startswith('{"type":"orca_server_ready"')), None
                    )
                    self.assertIsNotNone(line, "Orcad exited before reporting readiness")
                    ready = json.loads(line)
                    self.assertTrue(ready["boundEndpoint"].startswith("ws://127.0.0.1:"))
                    self.assertTrue(ready["health"]["terminalDaemon"]["selfTest"]["ok"], "Orcad PTY self-test failed")
                    result = subprocess.run(
                        [cli, "--pairing-code", ready["pairing"]["url"], "status", "--json"],
                        env=client_env,
                        text=True,
                        capture_output=True,
                        timeout=20,
                    )
                    self.assertEqual(result.returncode, 0, "could not pair with Orcad")
                    self.assertEqual(json.loads(result.stdout)["result"]["runtime"]["state"], "ready")
                finally:
                    server.terminate()
                    try:
                        server.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        server.kill()


if __name__ == "__main__":
    unittest.main()
