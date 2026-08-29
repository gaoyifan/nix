#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["pyyaml>=6,<7"]
# ///

import json
import os
import pathlib
import re
import sys
import urllib.request

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]
TARGET = ROOT / "nixos/hosts/el2/media-services.nix"
RELEASE_API = "https://api.github.com/repos/immich-app/immich/releases/latest"
IMAGE_PATTERNS = {
    "server": re.compile(r'(?m)^(\s*image = ")(?=ghcr\.io/immich-app/immich-server:)[^"]+(";)'),
    "redis": re.compile(r'(?m)^(\s*image = ")(?=docker\.io/valkey/valkey:)[^"]+(";)'),
    "postgres": re.compile(r'(?m)^(\s*image = ")(?=ghcr\.io/immich-app/postgres:)[^"]+(";)'),
}


def github_headers():
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "bump-immich",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def fetch_json(url):
    request = urllib.request.Request(url, headers=github_headers())
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def fetch_text(url):
    request = urllib.request.Request(url, headers=github_headers())
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def latest_compose():
    release = fetch_json(RELEASE_API)
    tag = release["tag_name"]
    if not isinstance(tag, str) or not re.fullmatch(r"v[0-9]+(?:\.[0-9]+)+", tag):
        raise RuntimeError(f"unexpected Immich release tag: {tag!r}")

    assets = release["assets"]
    compose_asset = next(
        (asset for asset in assets if asset["name"] == "docker-compose.yml"),
        None,
    )
    if compose_asset is None:
        raise RuntimeError(f"release {tag} has no docker-compose.yml asset")

    compose = yaml.safe_load(fetch_text(compose_asset["browser_download_url"]))
    services = compose["services"]
    images = {
        "server": f"ghcr.io/immich-app/immich-server:{tag}",
        "redis": services["redis"]["image"],
        "postgres": services["database"]["image"],
    }

    expected_prefixes = {
        "redis": "docker.io/valkey/valkey:",
        "postgres": "ghcr.io/immich-app/postgres:",
    }
    for name, prefix in expected_prefixes.items():
        image = images[name]
        if not isinstance(image, str) or not image.startswith(prefix):
            raise RuntimeError(f"unexpected official {name} image: {image!r}")

    return tag, images


def replace_image(text, name, image):
    pattern = IMAGE_PATTERNS[name]
    updated, count = pattern.subn(lambda match: f"{match[1]}{image}{match[2]}", text)
    if count != 1:
        raise RuntimeError(f"expected exactly one {name} image declaration, found {count}")
    return updated


def set_output(name, value):
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a") as output:
            print(f"{name}={value}", file=output)
    else:
        print(f"{name}={value}")


def main():
    tag, images = latest_compose()
    current = TARGET.read_text()
    updated = current
    for name in ("server", "redis", "postgres"):
        updated = replace_image(updated, name, images[name])

    changed = updated != current
    if changed:
        TARGET.write_text(updated)

    summary = "Immich images: " + ", ".join(f"{name}={images[name]}" for name in ("server", "redis", "postgres"))
    set_output("changed", "true" if changed else "false")
    set_output("files", str(TARGET.relative_to(ROOT)))
    set_output("commit_subject", f"chore(immich): bump to {tag}" if changed else "")
    set_output("commit_body", summary if changed else "")
    set_output("summary", summary)
    print(summary)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
