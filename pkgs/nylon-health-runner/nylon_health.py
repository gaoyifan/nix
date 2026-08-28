#!/usr/bin/env python3
"""Validate a Nylon manifest or run bounded live mesh health checks."""

from __future__ import annotations

import argparse
import base64
import ipaddress
import json
import re
import socket
import subprocess
import sys
from collections.abc import Mapping, Sequence
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any


NODE_NAME = re.compile(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?")
SHA256 = re.compile(r"[0-9a-f]{64}")
SSH_USER = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._-]*")
SSH_SUFFIX = re.compile(r"[A-Za-z0-9.-]*")
REMOTE_SCRIPT = r"""
set -eu
export LC_ALL=C
export PATH=/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin

window=$1
shift

printf 'CENTRAL\t'
sha256sum /run/nylon/central.yaml | awk '{print $1}'

if ! status=$(nylon status -i nylon0 --json); then
  printf 'ERROR\tstatus\tnylon status failed\n'
  exit 1
fi
printf 'STATUS\t'
printf '%s' "$status" | base64 | tr -d '\n'
printf '\n'

if ! logs=$(journalctl -u nylon --since "$window seconds ago" --no-pager --output=cat); then
  printf 'ERROR\tdispatch\tjournalctl failed\n'
  exit 1
fi
printf 'DISPATCH\t%s\n' "$(printf '%s\n' "$logs" | awk '/dispatch channel is full/{count++} END{print count+0}')"

ping_address() {
  address=$1
  case "$address" in
    *:*) family=6 ;;
    *) family=4 ;;
  esac
  if ping "-$family" -n -c 3 -W 2 -i 0.2 "$address" >/dev/null 2>&1 \
    || ping "-$family" -n -c 10 -W 2 -i 0.2 "$address" >/dev/null 2>&1; then
    result=ok
  else
    result=unreachable
  fi
  printf 'PING\t%s\t%s\t%s\n' "$family" "$address" "$result"
  test "$result" = ok
}

ping_failure=0
pids=""
for address in "$@"; do
  ping_address "$address" &
  pids="$pids $!"
done
for pid in $pids; do
  if ! wait "$pid"; then
    ping_failure=1
  fi
done
exit "$ping_failure"
""".lstrip()


class ManifestError(ValueError):
    """The supplied manifest cannot safely drive the health checks."""


def _object(value: object, field: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ManifestError(f"{field} must be an object")
    return value


def validate_manifest(raw: object) -> dict[str, Any]:
    manifest = _object(raw, "manifest")
    if manifest.get("schemaVersion") != 1:
        raise ManifestError("schemaVersion must be 1")

    central_sha256 = manifest.get("centralSha256")
    if not isinstance(central_sha256, str) or SHA256.fullmatch(central_sha256) is None:
        raise ManifestError("centralSha256 must be a lowercase SHA-256 digest")

    peer_names = manifest.get("peerNames")
    if not isinstance(peer_names, list) or not peer_names:
        raise ManifestError("peerNames must be a non-empty list")
    if not all(isinstance(name, str) and NODE_NAME.fullmatch(name) for name in peer_names):
        raise ManifestError("peerNames entries must be lower-case host labels")
    if len(set(peer_names)) != len(peer_names):
        raise ManifestError("peerNames contains duplicates")

    counts = _object(manifest.get("counts"), "counts")
    if counts.get("peers") != len(peer_names):
        raise ManifestError("counts.peers does not match peerNames")

    raw_nodes = _object(manifest.get("nodes"), "nodes")
    if set(raw_nodes) != set(peer_names):
        raise ManifestError("nodes keys must exactly match peerNames")

    nodes: dict[str, dict[str, Any]] = {}
    seen_addresses: set[ipaddress.IPv4Address | ipaddress.IPv6Address] = set()
    for name in peer_names:
        node = _object(raw_nodes[name], f"nodes.{name}")
        public_key = node.get("publicKey")
        if not isinstance(public_key, str) or not public_key:
            raise ManifestError(f"nodes.{name}.publicKey must be a non-empty string")
        raw_addresses = _object(node.get("addresses"), f"nodes.{name}.addresses")
        addresses: dict[str, str] = {}
        for field, version in (("ipv4", 4), ("ipv6", 6)):
            value = raw_addresses.get(field)
            if not isinstance(value, str):
                raise ManifestError(f"nodes.{name}.addresses.{field} must be a string")
            try:
                address = ipaddress.ip_address(value)
            except ValueError as exc:
                raise ManifestError(f"nodes.{name}.addresses.{field} is not an IP address") from exc
            if address.version != version:
                raise ManifestError(f"nodes.{name}.addresses.{field} is not IPv{version}")
            if address in seen_addresses:
                raise ManifestError(f"overlay address {address.compressed} is duplicated")
            seen_addresses.add(address)
            addresses[field] = address.compressed
        nodes[name] = {"publicKey": public_key, "addresses": addresses}

    return {
        "centralSha256": central_sha256,
        "peerNames": peer_names,
        "nodes": nodes,
    }


def load_manifest(path: str) -> dict[str, Any]:
    try:
        with Path(path).open(encoding="utf-8") as source:
            return validate_manifest(json.load(source))
    except (OSError, json.JSONDecodeError) as exc:
        raise ManifestError(f"cannot read manifest {path!r}: {exc}") from exc


def local_identity() -> tuple[set[str], set[str]]:
    names = {socket.gethostname().lower().rstrip(".")}
    names |= {name.split(".", 1)[0] for name in names}
    try:
        result = subprocess.run(
            ["ip", "-json", "address", "show"],
            text=True,
            capture_output=True,
            timeout=5,
            check=True,
        )
        links = json.loads(result.stdout)
        addresses = {
            info["local"]
            for link in links
            for info in link.get("addr_info", [])
            if isinstance(info, Mapping) and isinstance(info.get("local"), str)
        }
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, TypeError, KeyError) as exc:
        raise ManifestError(f"cannot inspect local addresses before SSH: {exc}") from exc
    return names, addresses


def is_local_member(
    name: str,
    manifest: Mapping[str, Any],
    suffix: str,
    local_names: set[str],
    local_addresses: set[str],
) -> bool:
    target = (name + suffix).lower().rstrip(".")
    node_addresses = set(manifest["nodes"][name]["addresses"].values())
    return name in local_names or target in local_names or bool(node_addresses & local_addresses)


def run_probe(
    name: str,
    manifest: Mapping[str, Any],
    *,
    local: bool,
    suffix: str,
    user: str | None,
    ssh_options: Sequence[str],
    connect_timeout: int,
    host_timeout: int,
    dispatch_window: int,
) -> subprocess.CompletedProcess[str] | subprocess.TimeoutExpired:
    addresses = [node["addresses"][family] for node in manifest["nodes"].values() for family in ("ipv4", "ipv6")]
    probe = (
        "sudo",
        "-n",
        "--",
        "/bin/sh",
        "-s",
        "--",
        str(dispatch_window),
        *addresses,
    )
    if local:
        command = list(probe)
    else:
        command = [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectionAttempts=1",
            "-o",
            f"ConnectTimeout={connect_timeout}",
        ]
        for option in ssh_options:
            command.extend(("-o", option))
        command.extend(
            (
                f"{user}@{name}{suffix}" if user else name + suffix,
                *probe,
            )
        )
    try:
        return subprocess.run(
            command,
            input=REMOTE_SCRIPT,
            text=True,
            capture_output=True,
            timeout=host_timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        return exc


def _records(output: str) -> tuple[dict[str, list[list[str]]], list[str]]:
    records: dict[str, list[list[str]]] = {}
    malformed: list[str] = []
    for line in output.splitlines():
        fields = line.split("\t")
        if fields[0] not in {"CENTRAL", "STATUS", "DISPATCH", "PING", "ERROR"}:
            malformed.append(line)
            continue
        records.setdefault(fields[0], []).append(fields[1:])
    return records, malformed


def _one_record(records: Mapping[str, list[list[str]]], kind: str, problems: list[str]) -> list[str] | None:
    matches = records.get(kind, [])
    if len(matches) != 1:
        problems.append(f"expected one {kind.lower()} result, found {len(matches)}")
        return None
    return matches[0]


def evaluate_remote(
    name: str,
    manifest: Mapping[str, Any],
    result: subprocess.CompletedProcess[str] | subprocess.TimeoutExpired,
    host_timeout: int,
) -> list[str]:
    if isinstance(result, subprocess.TimeoutExpired):
        return [f"remote probe exceeded {host_timeout}s host timeout"]

    records, malformed = _records(result.stdout)
    if not records:
        detail = result.stderr.strip().splitlines()
        suffix = f": {detail[-1]}" if detail else ": no structured output"
        return [f"SSH/remote probe exited {result.returncode}{suffix}"]
    problems = [f"unexpected remote output: {line!r}" for line in malformed]
    for error in records.get("ERROR", []):
        problems.append("remote " + ": ".join(error))

    central = _one_record(records, "CENTRAL", problems)
    if central is not None:
        if len(central) != 1 or central[0] != manifest["centralSha256"]:
            found = central[0] if central else "missing"
            problems.append(f"central digest is {found}, expected {manifest['centralSha256']}")

    status_record = _one_record(records, "STATUS", problems)
    if status_record is not None:
        try:
            if len(status_record) != 1:
                raise ValueError("status record has extra fields")
            status_document = json.loads(base64.b64decode(status_record[0], validate=True))
            status = _object(_object(status_document, "status document").get("status"), "status")
            node = _object(status.get("node"), "status.node")
            if node.get("nodeId") != name:
                problems.append(f"runtime member is {node.get('nodeId')!r}, expected {name!r}")
            expected_key = manifest["nodes"][name]["publicKey"]
            if node.get("publicKey") != expected_key:
                problems.append("runtime public key does not match manifest")

            expected_neighbours = set(manifest["peerNames"]) - {name}
            raw_neighbours = status.get("neighbours")
            if not isinstance(raw_neighbours, list):
                raise ManifestError("status.neighbours must be a list")
            neighbour_ids = {
                neighbour.get("peerId")
                for neighbour in raw_neighbours
                if isinstance(neighbour, Mapping) and isinstance(neighbour.get("peerId"), str)
            }
            if neighbour_ids != expected_neighbours or len(raw_neighbours) != len(expected_neighbours):
                missing = sorted(expected_neighbours - neighbour_ids)
                extra = sorted(neighbour_ids - expected_neighbours)
                problems.append(
                    f"neighbours do not match manifest (count={len(raw_neighbours)}, missing={missing}, extra={extra})"
                )
            inactive_neighbours = sorted(
                neighbour["peerId"]
                for neighbour in raw_neighbours
                if isinstance(neighbour, Mapping)
                and neighbour.get("peerId") in expected_neighbours
                and (
                    not isinstance(neighbour.get("linkCost"), int)
                    or neighbour["linkCost"] <= 0
                    or not isinstance(neighbour.get("endpoints"), list)
                    or not any(
                        isinstance(endpoint, Mapping) and endpoint.get("active") is True
                        for endpoint in neighbour["endpoints"]
                    )
                )
            )
            if inactive_neighbours:
                problems.append(f"neighbours have no active finite-cost link: {inactive_neighbours}")

            routes = _object(status.get("routes"), "status.routes")
            raw_selected = routes.get("selected")
            raw_forward = routes.get("forward")
            if not isinstance(raw_selected, list) or not isinstance(raw_forward, list):
                raise ManifestError("status.routes selected/forward must be lists")
            selected = {
                (source.get("nodeId"), source.get("prefix"))
                for route in raw_selected
                if isinstance(route, Mapping)
                and isinstance(route.get("pubRoute"), Mapping)
                and isinstance((source := route["pubRoute"].get("source")), Mapping)
            }
            expected_routes = {
                (peer_name, f"{node_data['addresses']['ipv4']}/32")
                for peer_name, node_data in manifest["nodes"].items()
                if peer_name != name
            } | {
                (peer_name, f"{node_data['addresses']['ipv6']}/128")
                for peer_name, node_data in manifest["nodes"].items()
                if peer_name != name
            }
            missing_routes = sorted(expected_routes - selected)
            if missing_routes:
                problems.append(f"selected routes missing manifest prefixes: {missing_routes}")
            expected_prefixes = {prefix for _, prefix in expected_routes}
            unreachable = sorted(
                route.get("prefix")
                for route in raw_forward
                if isinstance(route, Mapping)
                and route.get("blackhole") is True
                and route.get("prefix") in expected_prefixes
            )
            if unreachable:
                problems.append(f"manifest routes are unreachable: {unreachable}")
        except ValueError as exc:
            problems.append(f"invalid Nylon status result: {exc}")

    dispatch = _one_record(records, "DISPATCH", problems)
    if dispatch is not None:
        try:
            if len(dispatch) != 1 or int(dispatch[0]) < 0:
                raise ValueError
            if int(dispatch[0]) != 0:
                problems.append(f"dispatch channel was full {dispatch[0]} time(s)")
        except ValueError:
            problems.append(f"invalid dispatch count: {dispatch!r}")

    ping_results: dict[tuple[str, str], str] = {}
    for ping in records.get("PING", []):
        if len(ping) != 3 or ping[0] not in {"4", "6"} or ping[2] not in {"ok", "unreachable"}:
            problems.append(f"invalid ping result: {ping!r}")
            continue
        key = (ping[0], ping[1])
        if key in ping_results:
            problems.append(f"duplicate ping result for IPv{ping[0]} {ping[1]}")
        ping_results[key] = ping[2]
    expected_pings = {
        (family[-1], node["addresses"][family]) for node in manifest["nodes"].values() for family in ("ipv4", "ipv6")
    }
    missing_pings = sorted(expected_pings - set(ping_results))
    if missing_pings:
        problems.append(
            f"missing overlay ping results: {['IPv' + family + ' ' + address for family, address in missing_pings]}"
        )
    unreachable_pings = sorted(
        key for key, outcome in ping_results.items() if key in expected_pings and outcome != "ok"
    )
    if unreachable_pings:
        problems.append(
            f"unreachable overlay addresses: {['IPv' + family + ' ' + address for family, address in unreachable_pings]}"
        )
    unexpected_pings = sorted(set(ping_results) - expected_pings)
    if unexpected_pings:
        problems.append(
            f"unexpected overlay ping targets: {['IPv' + family + ' ' + address for family, address in unexpected_pings]}"
        )

    incomplete = (
        bool(records.get("ERROR"))
        or central is None
        or status_record is None
        or dispatch is None
        or bool(missing_pings)
    )
    if result.returncode != 0 and (incomplete or not problems):
        detail = result.stderr.strip().splitlines()
        suffix = f": {detail[-1]}" if detail else ""
        problems.append(f"remote probe exited {result.returncode}{suffix}")
    return problems


def check(manifest: Mapping[str, Any], args: argparse.Namespace) -> int:
    local_names, local_addresses = local_identity()
    common_arguments = {
        "suffix": args.ssh_suffix,
        "user": args.ssh_user,
        "ssh_options": args.ssh_option,
        "connect_timeout": args.connect_timeout,
        "host_timeout": args.host_timeout,
        "dispatch_window": args.dispatch_window,
    }
    with ThreadPoolExecutor(max_workers=min(5, len(manifest["peerNames"]))) as executor:
        futures = {
            name: executor.submit(
                run_probe,
                name,
                manifest,
                local=is_local_member(
                    name,
                    manifest,
                    args.ssh_suffix,
                    local_names,
                    local_addresses,
                ),
                **common_arguments,
            )
            for name in manifest["peerNames"]
        }

    failed = False
    for name in manifest["peerNames"]:
        problems = evaluate_remote(name, manifest, futures[name].result(), args.host_timeout)
        if problems:
            failed = True
            print(f"FAIL {name}")
            for problem in problems:
                print(f"  {problem}")
        else:
            print(
                f"PASS {name}: central/member/{len(manifest['peerNames']) - 1} neighbours, "
                f"{len(manifest['peerNames']) * 2} overlay targets, dispatch=0"
            )
    print(f"nylon health: {'FAIL' if failed else 'PASS'}")
    return 1 if failed else 0


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="nylon-health", description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser(
        "validate-manifest",
        help="validate a manifest locally without contacting any host",
    )
    validate_parser.add_argument("manifest", help="compiled Nylon manifest JSON")

    check_parser = subparsers.add_parser("check", help="run read-only checks on every manifest member")
    check_parser.add_argument("manifest", help="compiled Nylon manifest JSON")
    check_parser.add_argument("--ssh-suffix", default=".ts.gaof.net", help="suffix appended to each member name")
    check_parser.add_argument("--ssh-user", help="SSH user for every member (default: SSH configuration)")
    check_parser.add_argument(
        "--ssh-option",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="additional ssh -o option; may be repeated",
    )
    check_parser.add_argument("--connect-timeout", type=_positive_int, default=10, metavar="SECONDS")
    check_parser.add_argument("--host-timeout", type=_positive_int, default=45, metavar="SECONDS")
    check_parser.add_argument("--dispatch-window", type=_positive_int, default=120, metavar="SECONDS")

    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.manifest)
        if args.command == "validate-manifest":
            print(f"valid Nylon manifest: {len(manifest['peerNames'])} peers, central {manifest['centralSha256']}")
            return 0
        if SSH_SUFFIX.fullmatch(args.ssh_suffix) is None:
            raise ManifestError("--ssh-suffix may contain only letters, digits, dots, and hyphens")
        if args.ssh_user is not None and SSH_USER.fullmatch(args.ssh_user) is None:
            raise ManifestError("--ssh-user contains unsupported characters")
        return check(manifest, args)
    except ManifestError as exc:
        print(f"nylon-health: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
