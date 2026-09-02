#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["pyyaml>=6,<7"]
# ///

import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.request

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]
IMMICH_RELEASE_API = "https://api.github.com/repos/immich-app/immich/releases/latest"
TARGETS = {
    "immich-server": (ROOT / "nixos/hosts/el2/services/immich.nix", "ghcr.io/immich-app/immich-server"),
    "immich-redis": (ROOT / "nixos/hosts/el2/services/immich.nix", "docker.io/valkey/valkey"),
    "immich-postgres": (ROOT / "nixos/hosts/el2/services/immich.nix", "ghcr.io/immich-app/postgres"),
    "new-api": (ROOT / "nixos/hosts/el2/services/new-api.nix", "docker.io/calciumion/new-api"),
    "open-webui": (ROOT / "nixos/hosts/el2/services/open-webui.nix", "ghcr.io/open-webui/open-webui"),
    "py-kms": (ROOT / "nixos/hosts/el2/services/py-kms.nix", "ghcr.io/gaoyifan/py-kms"),
}
FLOATING_TAGS = {
    "new-api": "latest",
    "open-webui": "main",
    "py-kms": "master",
}


def fetch_text(url):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "bump-container-images",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def latest_immich_images():
    release = json.loads(fetch_text(IMMICH_RELEASE_API))
    tag = release["tag_name"]
    if not isinstance(tag, str) or not re.fullmatch(r"v[0-9]+(?:\.[0-9]+)+", tag):
        raise RuntimeError(f"unexpected Immich release tag: {tag!r}")

    compose_asset = next(
        (asset for asset in release["assets"] if asset["name"] == "docker-compose.yml"),
        None,
    )
    if compose_asset is None:
        raise RuntimeError(f"release {tag} has no docker-compose.yml asset")

    services = yaml.safe_load(fetch_text(compose_asset["browser_download_url"]))["services"]
    images = {
        "immich-server": f"ghcr.io/immich-app/immich-server:{tag}",
        "immich-redis": services["redis"]["image"],
        "immich-postgres": services["database"]["image"],
    }
    for name, image in images.items():
        repository = TARGETS[name][1]
        if not isinstance(image, str) or not re.fullmatch(rf"{re.escape(repository)}(?::|@).+", image):
            raise RuntimeError(f"unexpected official {name} image: {image!r}")
    return images


def resolve_digest(repository, tag):
    source = f"{repository}:{tag}"
    output = subprocess.check_output(
        ["docker", "buildx", "imagetools", "inspect", source, "--format", "{{json .Manifest}}"],
        text=True,
    )
    digest = json.loads(output)["digest"]
    if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise RuntimeError(f"unexpected digest for {source}: {digest!r}")
    return f"{repository}@{digest}"


def replace_image(text, name, image):
    repository = TARGETS[name][1]
    pattern = re.compile(rf'(?m)^(\s*image = ")({re.escape(repository)}(?=[:@])[^"]+)(";)')
    current = pattern.findall(text)
    if len(current) != 1:
        raise RuntimeError(f"expected exactly one {name} image declaration, found {len(current)}")
    updated = pattern.sub(lambda match: f"{match[1]}{image}{match[3]}", text)
    return updated, current[0][1]


def set_output(name, value):
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a") as output:
            if "\n" in value:
                print(f"{name}<<__GITHUB_OUTPUT_EOF__", file=output)
                print(value, file=output)
                print("__GITHUB_OUTPUT_EOF__", file=output)
            else:
                print(f"{name}={value}", file=output)
    else:
        print(f"{name}={value}")


def main():
    images = latest_immich_images()
    images.update({name: resolve_digest(TARGETS[name][1], tag) for name, tag in FLOATING_TAGS.items()})

    changes = []
    summaries = []
    for name, image in images.items():
        path = TARGETS[name][0]
        current_text = path.read_text()
        updated_text, current_image = replace_image(current_text, name, image)
        if updated_text != current_text:
            path.write_text(updated_text)
            changes.append((name, current_image, image))
            summaries.append(f"{name}: {current_image} -> {image}")
        else:
            summaries.append(f"{name}: {image}")

    summary = "; ".join(summaries)
    changed_files = sorted({TARGETS[name][0] for name, _, _ in changes})
    set_output("changed", "true" if changes else "false")
    set_output("files", " ".join(str(path.relative_to(ROOT)) for path in changed_files))
    set_output("commit_subject", "chore(containers): bump images" if changes else "")
    set_output("commit_body", "\n".join(f"- {name}: {current} -> {latest}" for name, current, latest in changes))
    set_output("summary", summary)
    print(summary)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
