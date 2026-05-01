#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[2]


PACKAGES = {
    "codex": {
        "path": ROOT / "pkgs/codex.nix",
        "release_api": "https://api.github.com/repos/openai/codex/releases?per_page=100",
        "version_from_tag": lambda tag: tag.removeprefix("rust-v"),
        "assets": {
            "x86_64-linux": "codex-x86_64-unknown-linux-musl.tar.gz",
            "aarch64-linux": "codex-aarch64-unknown-linux-musl.tar.gz",
            "aarch64-darwin": "codex-aarch64-apple-darwin.tar.gz",
        },
        "url": lambda version, asset: f"https://github.com/openai/codex/releases/download/rust-v{version}/{asset}",
    },
    "cursor-cli": {
        "path": ROOT / "pkgs/cursor-cli.nix",
        "assets": {
            "x86_64-linux": "linux/x64",
            "aarch64-linux": "linux/arm64",
            "aarch64-darwin": "darwin/arm64",
        },
        "url": lambda version, asset: f"https://downloads.cursor.com/lab/{version}/{asset}/agent-cli-package.tar.gz",
    },
}


def fetch_text(url, *, token=None, user_agent="bump-cli-packages"):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": user_agent}
    if token:
        headers["Authorization"] = f"Bearer {token}"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode()


def current_version(path):
    match = re.search(r'^\s*version = "([^"]+)";$', path.read_text(), re.MULTILINE)
    if not match:
        raise RuntimeError(f"could not find version in {path}")
    return match.group(1)


def latest_codex(config):
    releases = json.loads(fetch_text(config["release_api"], token=os.environ.get("GH_TOKEN")))
    required_assets = set(config["assets"].values())
    tag_pattern = re.compile(r"^rust-v[0-9]+\.[0-9]+\.[0-9]+$")

    for release in releases:
        tag = release.get("tag_name", "")
        assets = {asset["name"] for asset in release.get("assets", [])}
        if tag_pattern.match(tag) and required_assets <= assets:
            return config["version_from_tag"](tag)

    raise RuntimeError("could not find a Codex release with all required assets")


def latest_cursor_cli():
    script = fetch_text("https://cursor.com/install", user_agent="curl/8.0")
    match = re.search(r"https://downloads\.cursor\.com/lab/([^/]+)/\$\{OS\}/\$\{ARCH\}/agent-cli-package\.tar\.gz", script)
    if not match:
        raise RuntimeError("could not find Cursor CLI version in install script")
    return match.group(1)


def latest_version(name, config):
    if name == "codex":
        return latest_codex(config)
    if name == "cursor-cli":
        return latest_cursor_cli()
    raise RuntimeError(f"unsupported package: {name}")


def prefetch_hash(url):
    output = subprocess.check_output(["nix", "store", "prefetch-file", "--json", url], text=True)
    return json.loads(output)["hash"]


def update_package(name, config, version):
    path = config["path"]
    text = path.read_text()
    text, count = re.subn(r'version = "[^"]+";', f'version = "{version}";', text, count=1)
    if count != 1:
        raise RuntimeError(f"failed to update version in {path}")

    for system, asset in config["assets"].items():
        hash_value = prefetch_hash(config["url"](version, asset))
        pattern = (
            rf'({re.escape(system)} = \{{\n'
            rf'(?:        [a-z]+ = "[^"]+";\n)+'
            rf'        hash = ")[^"]+(";)'
        )
        text, count = re.subn(pattern, rf"\g<1>{hash_value}\2", text)
        if count != 1:
            raise RuntimeError(f"failed to update {system} hash in {path}")

    path.write_text(text)


def set_output(name, value):
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a") as output:
            print(f"{name}={value}", file=output)
    else:
        print(f"{name}={value}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", default="all", choices=["all", *PACKAGES])
    parser.add_argument("--version", default="")
    args = parser.parse_args()

    selected = list(PACKAGES) if args.package == "all" else [args.package]
    if args.version and len(selected) != 1:
        raise SystemExit("--version requires selecting one package")

    changed = []
    summaries = []

    for name in selected:
        config = PACKAGES[name]
        current = current_version(config["path"])
        latest = args.version or latest_version(name, config)
        summaries.append(f"{name}: {current} -> {latest}")

        if current == latest:
            continue

        update_package(name, config, latest)
        changed.append(name)

    set_output("changed", "true" if changed else "false")
    set_output("packages", " ".join(changed))
    set_output("files", " ".join(str(PACKAGES[name]["path"].relative_to(ROOT)) for name in changed))
    set_output("summary", "; ".join(summaries))

    for summary in summaries:
        print(summary)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
