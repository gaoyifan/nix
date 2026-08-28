from __future__ import annotations

import base64
import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import nylon_health


def manifest() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "centralSha256": "a" * 64,
        "peerNames": ["one", "two"],
        "counts": {"peers": 2},
        "nodes": {
            "one": {
                "publicKey": "key-one",
                "addresses": {"ipv4": "10.250.10.16", "ipv6": "fd10:250:10::16"},
            },
            "two": {
                "publicKey": "key-two",
                "addresses": {"ipv4": "10.250.10.17", "ipv6": "fd10:250:10::17"},
            },
        },
    }


def status_output(*, blackhole: bool = False) -> str:
    status = {
        "status": {
            "node": {"nodeId": "one", "publicKey": "key-one"},
            "neighbours": [{"peerId": "two", "linkCost": 1, "endpoints": [{"active": True}]}],
            "routes": {
                "selected": [
                    {"pubRoute": {"source": {"nodeId": name, "prefix": f"{address}/{bits}"}}}
                    for name, addresses in (("two", ("10.250.10.17", "fd10:250:10::17")),)
                    for address, bits in zip(addresses, (32, 128), strict=True)
                ],
                "forward": [
                    {"prefix": "10.250.10.17/32", "blackhole": blackhole},
                    {"prefix": "fd10:250:10::17/128", "blackhole": False},
                ],
            },
        }
    }
    encoded = base64.b64encode(json.dumps(status).encode()).decode()
    return "\n".join(
        (
            f"CENTRAL\t{'a' * 64}",
            f"STATUS\t{encoded}",
            "DISPATCH\t0",
            "PING\t4\t10.250.10.16\tok",
            "PING\t6\tfd10:250:10::16\tok",
            "PING\t4\t10.250.10.17\tok",
            "PING\t6\tfd10:250:10::17\tok",
        )
    )


class ManifestTests(unittest.TestCase):
    def test_valid_manifest_is_normalized(self) -> None:
        validated = nylon_health.validate_manifest(manifest())
        self.assertEqual(validated["peerNames"], ["one", "two"])
        self.assertEqual(validated["nodes"]["two"]["addresses"]["ipv6"], "fd10:250:10::17")

    def test_rejects_node_or_address_mismatch(self) -> None:
        cases = []
        missing_node = manifest()
        del missing_node["nodes"]["two"]
        cases.append(missing_node)
        wrong_family = manifest()
        wrong_family["nodes"]["two"]["addresses"]["ipv6"] = "10.250.10.17"
        cases.append(wrong_family)
        duplicate = manifest()
        duplicate["nodes"]["two"]["addresses"]["ipv4"] = "10.250.10.16"
        cases.append(duplicate)
        for invalid in cases:
            with self.subTest(invalid=invalid), self.assertRaises(nylon_health.ManifestError):
                nylon_health.validate_manifest(invalid)

    def test_validate_manifest_cli_never_invokes_ssh(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps(manifest()), encoding="utf-8")
            stdout = io.StringIO()
            with mock.patch.object(nylon_health.subprocess, "run") as run, contextlib.redirect_stdout(stdout):
                result = nylon_health.main(["validate-manifest", str(path)])
            self.assertEqual(result, 0)
            self.assertFalse(run.called)
            self.assertIn("valid Nylon manifest", stdout.getvalue())


class RuntimeResultTests(unittest.TestCase):
    def test_local_member_is_probed_without_ssh(self) -> None:
        validated = nylon_health.validate_manifest(manifest())
        self.assertTrue(
            nylon_health.is_local_member(
                "one",
                validated,
                ".ts.gaof.net",
                {"operator"},
                {"10.250.10.16"},
            )
        )
        with mock.patch.object(
            nylon_health.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 0, "", ""),
        ) as run:
            nylon_health.run_probe(
                "one",
                validated,
                local=True,
                suffix=".ts.gaof.net",
                user=None,
                ssh_options=[],
                connect_timeout=10,
                host_timeout=45,
                dispatch_window=120,
            )
        self.assertEqual(run.call_args.args[0][0], "sudo")
        self.assertNotIn("ssh", run.call_args.args[0])

    def test_accepts_matching_bounded_health_result(self) -> None:
        validated = nylon_health.validate_manifest(manifest())
        result = subprocess.CompletedProcess([], 0, status_output(), "")
        self.assertEqual(nylon_health.evaluate_remote("one", validated, result, 45), [])

    def test_reports_owned_runtime_failures(self) -> None:
        validated = nylon_health.validate_manifest(manifest())
        output = (
            status_output(blackhole=True)
            .replace("DISPATCH\t0", "DISPATCH\t2")
            .replace(
                "PING\t6\tfd10:250:10::17\tok",
                "PING\t6\tfd10:250:10::17\tunreachable",
            )
        )
        result = subprocess.CompletedProcess([], 1, output, "")
        problems = nylon_health.evaluate_remote("one", validated, result, 45)
        self.assertTrue(any("routes are unreachable" in problem for problem in problems))
        self.assertTrue(any("dispatch channel was full 2" in problem for problem in problems))
        self.assertTrue(any("unreachable overlay addresses" in problem for problem in problems))
        self.assertTrue(any("IPv6 fd10:250:10::17" in problem for problem in problems))

    def test_one_dispatch_match_fails_the_fixed_window(self) -> None:
        validated = nylon_health.validate_manifest(manifest())
        output = status_output().replace("DISPATCH\t0", "DISPATCH\t1")
        problems = nylon_health.evaluate_remote(
            "one",
            validated,
            subprocess.CompletedProcess([], 0, output, ""),
            45,
        )
        self.assertTrue(any("dispatch channel was full 1 time" in problem for problem in problems))

    def test_reports_an_inactive_configured_neighbour(self) -> None:
        validated = nylon_health.validate_manifest(manifest())
        output = status_output()
        status_line = next(line for line in output.splitlines() if line.startswith("STATUS\t"))
        status = json.loads(base64.b64decode(status_line.split("\t", 1)[1]))
        status["status"]["neighbours"][0]["linkCost"] = 0
        status["status"]["neighbours"][0]["endpoints"] = []
        replacement = "STATUS\t" + base64.b64encode(json.dumps(status).encode()).decode()
        problems = nylon_health.evaluate_remote(
            "one",
            validated,
            subprocess.CompletedProcess([], 0, output.replace(status_line, replacement), ""),
            45,
        )
        self.assertTrue(any("no active finite-cost link" in problem for problem in problems))

    def test_reports_member_and_neighbour_mismatch(self) -> None:
        validated = nylon_health.validate_manifest(manifest())
        encoded = status_output()
        status_line = next(line for line in encoded.splitlines() if line.startswith("STATUS\t"))
        status = json.loads(base64.b64decode(status_line.split("\t", 1)[1]))
        status["status"]["node"]["nodeId"] = "two"
        status["status"]["neighbours"] = []
        replacement = "STATUS\t" + base64.b64encode(json.dumps(status).encode()).decode()
        output = encoded.replace(status_line, replacement)
        problems = nylon_health.evaluate_remote("one", validated, subprocess.CompletedProcess([], 0, output, ""), 45)
        self.assertTrue(any("runtime member" in problem for problem in problems))
        self.assertTrue(any("neighbours do not match" in problem for problem in problems))


if __name__ == "__main__":
    unittest.main()
