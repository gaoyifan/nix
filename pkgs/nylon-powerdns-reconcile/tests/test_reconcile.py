from __future__ import annotations

import copy
import json
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import nylon_powerdns_reconcile as reconcile


ZONE = "ny.gaof.net."


def rrset(name: str, record_type: str, *contents: str, ttl: int = 300) -> dict[str, Any]:
    return {
        "name": name,
        "type": record_type,
        "ttl": ttl,
        "records": [{"content": content, "disabled": False} for content in contents],
    }


def snapshot(*rrsets: dict[str, Any]) -> dict[str, Any]:
    return {"zone": ZONE, "rrsets": list(rrsets)}


class FakePowerDNS:
    def __init__(self, rrsets: list[dict[str, Any]]):
        self.zone = {"name": ZONE, "serial": 1, "rrsets": copy.deepcopy(rrsets)}
        self.patch_bodies: list[dict[str, Any]] = []
        self.ignore_patches = False
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def _authorized(self) -> bool:
                if self.headers.get("X-API-Key") == "fixture-key":
                    return True
                self.send_response(401)
                self.end_headers()
                return False

            def do_GET(self) -> None:
                if not self._authorized():
                    return
                body = json.dumps(owner.zone).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_PATCH(self) -> None:
                if not self._authorized():
                    return
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                owner.patch_bodies.append(copy.deepcopy(body))
                if not owner.ignore_patches:
                    owner._apply(body["rrsets"])
                self.send_response(204)
                self.end_headers()

            def log_message(self, _format: str, *args: object) -> None:
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def _apply(self, changes: list[dict[str, Any]]) -> None:
        for change in changes:
            key = (change["name"].lower(), change["type"].upper())
            existing = [item for item in self.zone["rrsets"] if (item["name"].lower(), item["type"].upper()) == key]
            self.zone["rrsets"] = [
                item for item in self.zone["rrsets"] if (item["name"].lower(), item["type"].upper()) != key
            ]
            if change["changetype"] == "REPLACE":
                replacement = {field: copy.deepcopy(change[field]) for field in ("name", "type", "ttl", "records")}
                if existing and "comments" in existing[0]:
                    replacement["comments"] = copy.deepcopy(existing[0]["comments"])
                self.zone["rrsets"].append(replacement)
            elif change["changetype"] != "DELETE":
                raise AssertionError(f"unsupported fixture change {change!r}")
        self.zone["serial"] += 1

    def __enter__(self) -> "FakePowerDNS":
        self.thread.start()
        return self

    def __exit__(self, *_args: object) -> None:
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()

    @property
    def url(self) -> str:
        host, port = self.server.server_address
        return f"http://{host}:{port}/api/v1/servers/localhost/zones/{ZONE}"

    def client(self) -> reconcile.HTTPPowerDNSClient:
        return reconcile.HTTPPowerDNSClient(self.url, "fixture-key")


class ReconcileTests(unittest.TestCase):
    def test_matching_snapshot_is_idempotent_and_still_read_back(self) -> None:
        desired = snapshot(
            rrset("node.ny.gaof.net.", "A", "10.250.10.23"),
            rrset("node.ny.gaof.net.", "AAAA", "fd10:250:10::23"),
        )
        other = rrset("node.ny.gaof.net.", "TXT", '"owner=external"')
        with FakePowerDNS([*desired["rrsets"], other]) as server:
            planned = reconcile.plan(server.client(), desired)
            self.assertEqual(planned["changes"], [])
            self.assertEqual(planned["preimage_rrsets"], desired["rrsets"])

            result = reconcile.apply(server.client(), planned)

            self.assertFalse(result["changed"])
            self.assertEqual(server.patch_bodies, [])
            self.assertIn(other, server.zone["rrsets"])
            self.assertEqual(result["read_back_digest"], planned["desired_digest"])

    def test_apply_rejects_a_tampered_saved_preimage(self) -> None:
        desired = snapshot(rrset("node.ny.gaof.net.", "A", "10.250.10.23"))
        with FakePowerDNS([rrset("node.ny.gaof.net.", "A", "10.250.10.22")]) as server:
            planned = reconcile.plan(server.client(), desired)
            planned["preimage_rrsets"][0]["records"][0]["content"] = "10.250.10.99"

            with self.assertRaises(reconcile.InvalidPlan):
                reconcile.apply(server.client(), planned)

            self.assertEqual(server.patch_bodies, [])

    def test_apply_replaces_desired_and_deletes_stale_a_aaaa_only(self) -> None:
        txt = rrset("stale.ny.gaof.net.", "TXT", '"keep me"')
        current = [
            rrset("node.ny.gaof.net.", "A", "10.250.10.99"),
            rrset("stale.ny.gaof.net.", "A", "10.250.10.2"),
            rrset("stale.ny.gaof.net.", "AAAA", "fd10:250:10::2"),
            txt,
        ]
        desired = snapshot(
            rrset("node.ny.gaof.net.", "A", "10.250.10.23"),
            rrset("node.ny.gaof.net.", "AAAA", "fd10:250:10::23"),
        )
        with FakePowerDNS(current) as server:
            planned = reconcile.plan(server.client(), desired)
            self.assertEqual(
                [(change["name"], change["type"], change["changetype"]) for change in planned["changes"]],
                [
                    ("node.ny.gaof.net.", "A", "REPLACE"),
                    ("node.ny.gaof.net.", "AAAA", "REPLACE"),
                    ("stale.ny.gaof.net.", "A", "DELETE"),
                    ("stale.ny.gaof.net.", "AAAA", "DELETE"),
                ],
            )

            result = reconcile.apply(server.client(), planned)

            self.assertTrue(result["changed"])
            self.assertEqual(result["changes_applied"], 4)
            self.assertEqual(len(server.patch_bodies), 1)
            self.assertIn(txt, server.zone["rrsets"])
            after = reconcile.managed_snapshot(server.zone, ZONE)
            self.assertEqual(after, reconcile.canonical_snapshot(desired))

    def test_apply_ignores_unrelated_txt_soa_and_serial_changes(self) -> None:
        current_a = rrset("node.ny.gaof.net.", "A", "10.250.10.22")
        txt = rrset("metadata.ny.gaof.net.", "TXT", '"before"')
        soa = rrset(
            ZONE,
            "SOA",
            "ns1.gaof.net. hostmaster.gaof.net. 1 10800 3600 604800 3600",
        )
        desired = snapshot(rrset("node.ny.gaof.net.", "A", "10.250.10.23"))
        with FakePowerDNS([current_a, txt, soa]) as server:
            planned = reconcile.plan(server.client(), desired)
            self.assertEqual(planned["preimage_rrsets"], [current_a])

            server.zone["serial"] = 42
            server.zone["rrsets"][1]["records"][0]["content"] = '"after"'
            server.zone["rrsets"][2]["records"][0]["content"] = (
                "ns1.gaof.net. hostmaster.gaof.net. 2 10800 3600 604800 3600"
            )

            result = reconcile.apply(server.client(), planned)

            self.assertTrue(result["changed"])
            self.assertEqual(result["changes_applied"], 1)
            self.assertEqual(server.zone["serial"], 43)
            after_by_key = {(item["name"], item["type"]): item for item in server.zone["rrsets"]}
            self.assertEqual(after_by_key[("node.ny.gaof.net.", "A")], desired["rrsets"][0])
            self.assertEqual(after_by_key[("metadata.ny.gaof.net.", "TXT")]["records"][0]["content"], '"after"')
            self.assertEqual(
                after_by_key[(ZONE, "SOA")]["records"][0]["content"],
                "ns1.gaof.net. hostmaster.gaof.net. 2 10800 3600 604800 3600",
            )

    def test_apply_rejects_changed_a_or_aaaa_preimage_without_patching(self) -> None:
        cases = (
            ("A", "10.250.10.22", "10.250.10.23", "10.250.10.99"),
            ("AAAA", "fd10:250:10::22", "fd10:250:10::23", "fd10:250:10::99"),
        )
        for record_type, before, desired_content, changed in cases:
            with self.subTest(record_type=record_type):
                desired = snapshot(rrset("node.ny.gaof.net.", record_type, desired_content))
                with FakePowerDNS([rrset("node.ny.gaof.net.", record_type, before)]) as server:
                    planned = reconcile.plan(server.client(), desired)
                    server.zone["rrsets"][0]["records"][0]["content"] = changed

                    with self.assertRaises(reconcile.PreimageChanged):
                        reconcile.apply(server.client(), planned)

                    self.assertEqual(server.patch_bodies, [])

    def test_apply_rejects_failed_read_back(self) -> None:
        desired = snapshot(rrset("node.ny.gaof.net.", "A", "10.250.10.23"))
        with FakePowerDNS([]) as server:
            planned = reconcile.plan(server.client(), desired)
            server.ignore_patches = True

            with self.assertRaises(reconcile.ReadBackMismatch):
                reconcile.apply(server.client(), planned)

            self.assertEqual(len(server.patch_bodies), 1)

    def test_plan_refuses_to_delete_an_rrset_with_comments(self) -> None:
        stale = rrset("stale.ny.gaof.net.", "A", "10.250.10.2")
        stale["comments"] = [{"content": "owned elsewhere", "account": "ops", "modified_at": 1}]
        with FakePowerDNS([stale]) as server:
            with self.assertRaises(reconcile.UnsafeCommentDeletion):
                reconcile.plan(server.client(), snapshot())

            self.assertEqual(server.patch_bodies, [])

    def test_apply_refuses_a_comment_added_to_a_planned_delete(self) -> None:
        stale = rrset("stale.ny.gaof.net.", "A", "10.250.10.2")
        with FakePowerDNS([stale]) as server:
            planned = reconcile.plan(server.client(), snapshot())
            server.zone["rrsets"][0]["comments"] = [{"content": "added after plan", "account": "ops", "modified_at": 2}]

            with self.assertRaises(reconcile.UnsafeCommentDeletion):
                reconcile.apply(server.client(), planned)

            self.assertEqual(server.patch_bodies, [])

    def test_patch_response_loss_is_recovered_by_read_back(self) -> None:
        desired = snapshot(rrset("node.ny.gaof.net.", "A", "10.250.10.23"))
        with FakePowerDNS([]) as server:
            client = server.client()
            planned = reconcile.plan(client, desired)

            class LostResponseClient:
                def get_zone(self) -> dict[str, Any]:
                    return client.get_zone()

                def patch_zone(self, changes: list[dict[str, Any]]) -> None:
                    client.patch_zone(changes)
                    raise reconcile.ReconcileError("simulated lost PATCH response")

            result = reconcile.apply(LostResponseClient(), planned)

            self.assertTrue(result["patch_response_lost"])
            self.assertEqual(result["read_back_digest"], planned["desired_digest"])

    def test_http_error_does_not_include_untrusted_response_body(self) -> None:
        secret = "fixture-key"

        class ErrorHandler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                body = f"received X-API-Key: {self.headers.get('X-API-Key')}".encode()
                self.send_response(500)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, _format: str, *args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), ErrorHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            host, port = server.server_address
            client = reconcile.HTTPPowerDNSClient(f"http://{host}:{port}/zone", secret)
            with self.assertRaises(reconcile.ReconcileError) as failure:
                client.get_zone()
            self.assertNotIn(secret, str(failure.exception))
            self.assertEqual(str(failure.exception), "PowerDNS GET failed with HTTP 500")
        finally:
            server.shutdown()
            thread.join()
            server.server_close()

    def test_redirect_is_not_followed_with_the_api_key(self) -> None:
        received: list[str | None] = []

        class SinkHandler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                received.append(self.headers.get("X-API-Key"))
                self.send_response(200)
                self.end_headers()

            def log_message(self, _format: str, *args: object) -> None:
                pass

        sink = ThreadingHTTPServer(("127.0.0.1", 0), SinkHandler)
        sink_thread = threading.Thread(target=sink.serve_forever, daemon=True)
        sink_thread.start()
        sink_host, sink_port = sink.server_address

        class RedirectHandler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                self.send_response(302)
                self.send_header("Location", f"http://{sink_host}:{sink_port}/stolen")
                self.end_headers()

            def log_message(self, _format: str, *args: object) -> None:
                pass

        redirect = ThreadingHTTPServer(("127.0.0.1", 0), RedirectHandler)
        redirect_thread = threading.Thread(target=redirect.serve_forever, daemon=True)
        redirect_thread.start()
        try:
            host, port = redirect.server_address
            client = reconcile.HTTPPowerDNSClient(f"http://{host}:{port}/zone", "fixture-key")
            with self.assertRaises(reconcile.ReconcileError) as failure:
                client.get_zone()
            self.assertEqual(str(failure.exception), "PowerDNS GET failed with HTTP 302")
            self.assertEqual(received, [])
        finally:
            redirect.shutdown()
            redirect_thread.join()
            redirect.server_close()
            sink.shutdown()
            sink_thread.join()
            sink.server_close()

    def test_api_key_reader_only_trims_line_endings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "credential"
            path.write_text(" key with spaces \r\n", encoding="utf-8")
            self.assertEqual(reconcile._read_api_key(str(path)), " key with spaces ")


if __name__ == "__main__":
    unittest.main()
