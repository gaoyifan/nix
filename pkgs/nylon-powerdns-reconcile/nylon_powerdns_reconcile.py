#!/usr/bin/env python3
"""Reconcile a compiled Nylon DNS snapshot with one PowerDNS zone."""

from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import sys
import urllib.error
import urllib.request
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any, Protocol


MANAGED_TYPES = frozenset({"A", "AAAA"})
PLAN_SCHEMA = 1


class ReconcileError(RuntimeError):
    """Base class for safe reconciliation failures."""


class InvalidSnapshot(ReconcileError):
    """The desired snapshot or PowerDNS response is malformed."""


class InvalidPlan(ReconcileError):
    """The saved plan is malformed or has been modified."""


class PreimageChanged(ReconcileError):
    """Managed records changed after the plan was created."""


class ReadBackMismatch(ReconcileError):
    """PowerDNS did not retain the requested managed snapshot."""


class UnsafeCommentDeletion(ReconcileError):
    """A managed RRset deletion would also destroy external comments."""


class PatchOutcomeUncertain(ReconcileError):
    """PowerDNS may have applied a PATCH whose response was lost."""


class PowerDNSClient(Protocol):
    def get_zone(self) -> Mapping[str, Any]: ...

    def patch_zone(self, changes: Sequence[Mapping[str, Any]]) -> None: ...


def _absolute_name(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise InvalidSnapshot(f"{field} must be a non-empty string")
    return value.strip().rstrip(".").lower() + "."


def _is_in_zone(name: str, zone: str) -> bool:
    return name == zone or name.endswith("." + zone)


def _canonical_rrset(raw: object, zone: str) -> dict[str, Any]:
    if not isinstance(raw, Mapping):
        raise InvalidSnapshot("each rrset must be an object")

    name = _absolute_name(raw.get("name"), "rrset.name")
    if not _is_in_zone(name, zone):
        raise InvalidSnapshot(f"rrset {name} is outside zone {zone}")

    record_type = raw.get("type")
    if not isinstance(record_type, str) or record_type.upper() not in MANAGED_TYPES:
        raise InvalidSnapshot("managed rrset.type must be A or AAAA")
    record_type = record_type.upper()

    ttl = raw.get("ttl")
    if isinstance(ttl, bool) or not isinstance(ttl, int) or ttl <= 0:
        raise InvalidSnapshot(f"{name} {record_type} ttl must be a positive integer")

    raw_records = raw.get("records")
    if not isinstance(raw_records, list) or not raw_records:
        raise InvalidSnapshot(f"{name} {record_type} records must be a non-empty list")

    records: list[dict[str, Any]] = []
    for raw_record in raw_records:
        if not isinstance(raw_record, Mapping):
            raise InvalidSnapshot(f"{name} {record_type} record must be an object")
        content = raw_record.get("content")
        if not isinstance(content, str):
            raise InvalidSnapshot(f"{name} {record_type} record content must be a string")
        try:
            address = ipaddress.ip_address(content)
        except ValueError as exc:
            raise InvalidSnapshot(f"invalid {record_type} address {content!r}") from exc
        expected_version = 4 if record_type == "A" else 6
        if address.version != expected_version:
            raise InvalidSnapshot(f"{content!r} does not match rrset type {record_type}")
        disabled = raw_record.get("disabled", False)
        if not isinstance(disabled, bool):
            raise InvalidSnapshot(f"{name} {record_type} disabled must be boolean")
        records.append({"content": address.compressed, "disabled": disabled})

    records.sort(key=lambda record: (record["content"], record["disabled"]))
    if len({(record["content"], record["disabled"]) for record in records}) != len(records):
        raise InvalidSnapshot(f"{name} {record_type} contains duplicate records")
    return {"name": name, "type": record_type, "ttl": ttl, "records": records}


def _canonical_rrsets(raw_rrsets: object, zone: str) -> list[dict[str, Any]]:
    if not isinstance(raw_rrsets, list):
        raise InvalidSnapshot("rrsets must be a list")
    rrsets = [_canonical_rrset(raw, zone) for raw in raw_rrsets]
    rrsets.sort(key=lambda rrset: (rrset["name"], rrset["type"]))
    keys = [(rrset["name"], rrset["type"]) for rrset in rrsets]
    if len(set(keys)) != len(keys):
        raise InvalidSnapshot("snapshot contains duplicate name/type rrsets")
    return rrsets


def canonical_snapshot(raw: object) -> dict[str, Any]:
    if not isinstance(raw, Mapping):
        raise InvalidSnapshot("snapshot must be an object")
    zone = _absolute_name(raw.get("zone"), "zone")
    return {"zone": zone, "rrsets": _canonical_rrsets(raw.get("rrsets"), zone)}


def managed_snapshot(zone_document: object, expected_zone: str) -> dict[str, Any]:
    if not isinstance(zone_document, Mapping):
        raise InvalidSnapshot("PowerDNS zone response must be an object")
    zone = _absolute_name(zone_document.get("name"), "PowerDNS zone name")
    if zone != expected_zone:
        raise InvalidSnapshot(f"PowerDNS returned zone {zone}, expected {expected_zone}")
    raw_rrsets = zone_document.get("rrsets")
    if not isinstance(raw_rrsets, list):
        raise InvalidSnapshot("PowerDNS zone response has no rrsets list")
    managed = [
        raw
        for raw in raw_rrsets
        if isinstance(raw, Mapping) and isinstance(raw.get("type"), str) and raw["type"].upper() in MANAGED_TYPES
    ]
    return {"zone": zone, "rrsets": _canonical_rrsets(managed, zone)}


def snapshot_digest(snapshot: Mapping[str, Any]) -> str:
    encoded = json.dumps(
        snapshot,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def _changes(current: Mapping[str, Any], desired: Mapping[str, Any]) -> list[dict[str, Any]]:
    current_by_key = {(rrset["name"], rrset["type"]): rrset for rrset in current["rrsets"]}
    desired_by_key = {(rrset["name"], rrset["type"]): rrset for rrset in desired["rrsets"]}
    changes: list[dict[str, Any]] = []
    for key in sorted(current_by_key.keys() | desired_by_key.keys()):
        before = current_by_key.get(key)
        after = desired_by_key.get(key)
        if after is None:
            changes.append({"name": key[0], "type": key[1], "changetype": "DELETE"})
        elif before != after:
            changes.append({**after, "changetype": "REPLACE"})
    return changes


def _build_plan(current: Mapping[str, Any], desired: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "schema": PLAN_SCHEMA,
        "zone": desired["zone"],
        "preimage_digest": snapshot_digest(current),
        "preimage_rrsets": current["rrsets"],
        "desired_digest": snapshot_digest(desired),
        "desired_rrsets": desired["rrsets"],
        "changes": _changes(current, desired),
    }


def _reject_comment_deletions(
    zone_document: object,
    current: Mapping[str, Any],
    desired: Mapping[str, Any],
) -> None:
    """Refuse DELETEs that would discard comments owned outside this tool."""
    if not isinstance(zone_document, Mapping) or not isinstance(zone_document.get("rrsets"), list):
        raise InvalidSnapshot("PowerDNS zone response has no rrsets list")
    deleted = {
        (change["name"], change["type"]) for change in _changes(current, desired) if change["changetype"] == "DELETE"
    }
    for raw in zone_document["rrsets"]:
        if not isinstance(raw, Mapping):
            continue
        raw_type = raw.get("type")
        raw_name = raw.get("name")
        if not isinstance(raw_type, str) or raw_type.upper() not in MANAGED_TYPES:
            continue
        key = (_absolute_name(raw_name, "rrset.name"), raw_type.upper())
        if key in deleted and raw.get("comments"):
            raise UnsafeCommentDeletion(f"refusing to delete {key[0]} {key[1]} because it has PowerDNS comments")


def plan(client: PowerDNSClient, raw_snapshot: object) -> dict[str, Any]:
    desired = canonical_snapshot(raw_snapshot)
    zone_document = client.get_zone()
    current = managed_snapshot(zone_document, desired["zone"])
    _reject_comment_deletions(zone_document, current, desired)
    return _build_plan(current, desired)


def _snapshots_from_plan(
    raw_plan: object,
) -> tuple[Mapping[str, Any], Mapping[str, Any], Mapping[str, Any]]:
    if not isinstance(raw_plan, Mapping):
        raise InvalidPlan("plan must be an object")
    if raw_plan.get("schema") != PLAN_SCHEMA:
        raise InvalidPlan(f"unsupported plan schema {raw_plan.get('schema')!r}")
    try:
        preimage = canonical_snapshot({"zone": raw_plan.get("zone"), "rrsets": raw_plan.get("preimage_rrsets")})
        desired = canonical_snapshot({"zone": raw_plan.get("zone"), "rrsets": raw_plan.get("desired_rrsets")})
    except InvalidSnapshot as exc:
        raise InvalidPlan(str(exc)) from exc
    desired_digest = raw_plan.get("desired_digest")
    if desired_digest != snapshot_digest(desired):
        raise InvalidPlan("desired snapshot digest does not match plan contents")
    preimage_digest = raw_plan.get("preimage_digest")
    if (
        not isinstance(preimage_digest, str)
        or len(preimage_digest) != 64
        or any(character not in "0123456789abcdef" for character in preimage_digest)
    ):
        raise InvalidPlan("preimage_digest must be a lowercase SHA-256 digest")
    if preimage_digest != snapshot_digest(preimage):
        raise InvalidPlan("preimage snapshot digest does not match plan contents")
    if not isinstance(raw_plan.get("changes"), list):
        raise InvalidPlan("plan changes must be a list")
    if raw_plan["changes"] != _changes(preimage, desired):
        raise InvalidPlan("plan changes do not match its saved preimage and desired snapshot")
    return raw_plan, preimage, desired


def apply(client: PowerDNSClient, raw_plan: object) -> dict[str, Any]:
    saved_plan, preimage, desired = _snapshots_from_plan(raw_plan)
    zone_document = client.get_zone()
    current = managed_snapshot(zone_document, desired["zone"])
    current_digest = snapshot_digest(current)
    if current != preimage:
        raise PreimageChanged(
            f"managed PowerDNS preimage changed: planned {saved_plan['preimage_digest']}, found {current_digest}"
        )

    _reject_comment_deletions(zone_document, current, desired)

    changes = saved_plan["changes"]
    desired_digest = saved_plan["desired_digest"]
    if changes:
        try:
            client.patch_zone(changes)
        except ReconcileError as patch_error:
            try:
                recovered = managed_snapshot(client.get_zone(), desired["zone"])
            except ReconcileError as read_back_error:
                raise PatchOutcomeUncertain(
                    "PowerDNS PATCH outcome is uncertain because its response and read-back both failed"
                ) from read_back_error
            recovered_digest = snapshot_digest(recovered)
            if recovered_digest == desired_digest:
                return {
                    "zone": desired["zone"],
                    "changed": True,
                    "changes_applied": len(changes),
                    "patch_response_lost": True,
                    "preimage_digest": current_digest,
                    "read_back_digest": recovered_digest,
                }
            if recovered_digest == current_digest:
                raise ReconcileError(
                    "PowerDNS PATCH failed and read-back confirms that the preimage remains"
                ) from patch_error
            raise PatchOutcomeUncertain(
                "PowerDNS PATCH outcome is uncertain because read-back matches neither preimage nor desired state"
            ) from patch_error

    read_back = managed_snapshot(client.get_zone(), desired["zone"])
    read_back_digest = snapshot_digest(read_back)
    if read_back_digest != desired_digest:
        raise ReadBackMismatch(
            "managed PowerDNS read-back differs from desired snapshot: "
            f"expected {desired_digest}, found {read_back_digest}"
        )
    return {
        "zone": desired["zone"],
        "changed": bool(changes),
        "changes_applied": len(changes),
        "preimage_digest": current_digest,
        "read_back_digest": read_back_digest,
    }


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: Any,
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> None:
        return None


class HTTPPowerDNSClient:
    def __init__(self, zone_url: str, api_key: str, timeout: float = 15.0):
        self.zone_url = zone_url
        self.api_key = api_key
        self.timeout = timeout

    def _request(self, method: str, body: object | None = None) -> tuple[int, bytes]:
        data = None
        headers = {"Accept": "application/json", "X-API-Key": self.api_key}
        if body is not None:
            data = json.dumps(body, separators=(",", ":")).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(self.zone_url, data=data, headers=headers, method=method)
        try:
            opener = urllib.request.build_opener(_NoRedirectHandler())
            with opener.open(request, timeout=self.timeout) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as exc:
            raise ReconcileError(f"PowerDNS {method} failed with HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            raise ReconcileError(f"PowerDNS {method} failed: {exc.reason}") from exc

    def get_zone(self) -> Mapping[str, Any]:
        status, body = self._request("GET")
        if status != 200:
            raise ReconcileError(f"PowerDNS GET returned HTTP {status}, expected 200")
        try:
            result = json.loads(body)
        except json.JSONDecodeError as exc:
            raise ReconcileError("PowerDNS GET returned invalid JSON") from exc
        if not isinstance(result, Mapping):
            raise ReconcileError("PowerDNS GET returned a non-object JSON value")
        return result

    def patch_zone(self, changes: Sequence[Mapping[str, Any]]) -> None:
        status, _ = self._request("PATCH", {"rrsets": list(changes)})
        if status != 204:
            raise ReconcileError(f"PowerDNS PATCH returned HTTP {status}, expected 204")


def _read_json(path: str) -> object:
    if path == "-":
        return json.load(sys.stdin)
    with open(path, encoding="utf-8") as source:
        return json.load(source)


def _add_connection_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--url", required=True, help="PowerDNS zone API URL")
    parser.add_argument(
        "--api-key-file",
        required=True,
        help="runtime file containing the PowerDNS API key",
    )
    parser.add_argument("--timeout", type=float, default=15.0)


def _read_api_key(path: str) -> str:
    api_key = Path(path).read_text(encoding="utf-8").strip("\r\n")
    if not api_key:
        raise ReconcileError(f"PowerDNS API key file {path!r} is empty")
    if "\n" in api_key or "\r" in api_key:
        raise ReconcileError(f"PowerDNS API key file {path!r} must contain one line")
    return api_key


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan_parser = subparsers.add_parser("plan", help="read PowerDNS and emit a plan")
    _add_connection_arguments(plan_parser)
    plan_parser.add_argument("--snapshot", required=True, help="snapshot JSON file or -")

    apply_parser = subparsers.add_parser("apply", help="compare the preimage, patch, and verify read-back")
    _add_connection_arguments(apply_parser)
    apply_parser.add_argument("--plan", required=True, help="plan JSON file or -")

    args = parser.parse_args(argv)
    try:
        client = HTTPPowerDNSClient(args.url, _read_api_key(args.api_key_file), args.timeout)
        if args.command == "plan":
            result = plan(client, _read_json(args.snapshot))
        else:
            result = apply(client, _read_json(args.plan))
    except (OSError, json.JSONDecodeError, ReconcileError) as exc:
        print(f"nylon-powerdns-reconcile: {exc}", file=sys.stderr)
        return 1
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
