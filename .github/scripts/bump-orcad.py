#!/usr/bin/env python3
import argparse
import base64
import json
import os
import re
import urllib.request
from pathlib import Path


PACKAGE = Path(__file__).resolve().parents[2] / "pkgs/orcad.nix"
RELEASES = "https://api.github.com/repos/stablyai/orca/releases"
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
VERSION_PIN = re.compile(r'(?m)^(\s*version = ")([0-9.]+)(";)$')
ASSETS = ("orca-server-linux-x64.tar.gz", "orca-server-linux-arm64.tar.gz")
CHECKSUMS = "orca-server-sha256sums.txt"


def fetch_release(version):
    endpoint = f"tags/v{version}" if version else "latest"
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "bump-orcad"}
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(f"{RELEASES}/{endpoint}", headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def update_pin(text, release, requested=None):
    current = VERSION_PIN.search(text).group(2)
    tag = release["tag_name"]
    version = tag.removeprefix("v")
    if tag != f"v{version}" or not VERSION.fullmatch(version) or release["draft"] or release["prerelease"]:
        raise ValueError(f"expected a published stable Orca release, got {tag}")
    if requested and version != requested:
        raise ValueError(f"requested Orca {requested}, got {tag}")
    if version == current or (
        not requested and tuple(map(int, version.split("."))) < tuple(map(int, current.split(".")))
    ):
        print(f"Orcad stays at {current} (upstream: {version})")
        return text, current

    uploaded = {asset["name"]: asset for asset in release["assets"] if asset["state"] == "uploaded"}
    missing = set((*ASSETS, CHECKSUMS)) - uploaded.keys()
    if missing:
        message = f"Orca {tag} is missing published server assets: {', '.join(sorted(missing))}"
        if requested:
            raise ValueError(message)
        print(message)
        return text, current

    updated = VERSION_PIN.sub(rf"\g<1>{version}\3", text, count=1)
    for name in ASSETS:
        arch = name.removeprefix("orca-server-linux-").removesuffix(".tar.gz")
        digest = uploaded[name].get("digest") or ""
        match = re.fullmatch(r"sha256:([0-9a-f]{64})", digest)
        if not match:
            raise ValueError(f"invalid GitHub SHA-256 digest for {name}")
        sri = "sha256-" + base64.b64encode(bytes.fromhex(match[1])).decode("ascii")
        pattern = rf'(arch = "{arch}";\n\s*hash = ")[^"]+(";)'
        updated, count = re.subn(pattern, rf"\g<1>{sri}\2", updated)
        if count != 1:
            raise ValueError(f"expected one {arch} hash pin in {PACKAGE}")

    print(f"Orcad {current} -> {version}")
    return updated, version


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default=None, help="an explicit stable version, without the v prefix")
    args = parser.parse_args()
    if args.version and not VERSION.fullmatch(args.version):
        parser.error("--version must be a stable version in the form X.Y.Z")

    text = PACKAGE.read_text()
    updated, version = update_pin(text, fetch_release(args.version), args.version)
    if updated != text:
        PACKAGE.write_text(updated)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as stream:
            print(f"changed={str(updated != text).lower()}", file=stream)
            print(f"version={version}", file=stream)


if __name__ == "__main__":
    main()
