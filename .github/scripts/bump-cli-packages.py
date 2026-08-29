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

# Excluded from "all" (scheduled) bumps; can still be bumped explicitly via
# workflow_dispatch. antigravity-cli, copilot-cli, and cursor-cli are
# intentionally manual-only.
AUTO_BUMP_SKIP = {"antigravity-cli", "copilot-cli", "cursor-cli"}


PACKAGES = {
    "antigravity-cli": {
        "path": ROOT / "pkgs/antigravity-cli.nix",
        "manifest_base": "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app",
        "manifests": {
            "x86_64-linux": "linux_amd64",
            "aarch64-linux": "linux_arm64",
            "aarch64-darwin": "darwin_arm64",
        },
        "assets": {
            "x86_64-linux": "linux-x64/cli_linux_x64.tar.gz",
            "aarch64-linux": "linux-arm/cli_linux_arm64.tar.gz",
            "aarch64-darwin": "darwin-arm/cli_mac_arm64.tar.gz",
        },
        "url": lambda version, asset: (
            f"https://storage.googleapis.com/antigravity-public/antigravity-cli/{version}/{asset}"
        ),
    },
    "copilot-cli": {
        "path": ROOT / "pkgs/copilot-cli.nix",
        "release_api": "https://api.github.com/repos/github/copilot-cli/releases?per_page=100",
        "tag_pattern": r"^v[0-9]+\.[0-9]+\.[0-9]+$",
        "version_from_tag": lambda tag: tag.removeprefix("v"),
        "assets": {
            "x86_64-linux": "copilot-linux-x64.tar.gz",
            "aarch64-linux": "copilot-linux-arm64.tar.gz",
            "aarch64-darwin": "copilot-darwin-arm64.tar.gz",
        },
        "url": lambda version, asset: f"https://github.com/github/copilot-cli/releases/download/v{version}/{asset}",
    },
    "codex": {
        "path": ROOT / "pkgs/codex.nix",
        "release_api": "https://api.github.com/repos/openai/codex/releases?per_page=100",
        "tag_pattern": r"^rust-v[0-9]+\.[0-9]+\.[0-9]+$",
        "version_from_tag": lambda tag: tag.removeprefix("rust-v"),
        "assets": {
            "x86_64-linux": "codex-package-x86_64-unknown-linux-musl.tar.gz",
            "aarch64-linux": "codex-package-aarch64-unknown-linux-musl.tar.gz",
            "aarch64-darwin": "codex-package-aarch64-apple-darwin.tar.gz",
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
    "pi-coding-agent": {
        "path": ROOT / "pkgs/pi-coding-agent.nix",
        "release_api": "https://api.github.com/repos/earendil-works/pi/releases?per_page=100",
        "tag_pattern": r"^v[0-9]+\.[0-9]+\.[0-9]+$",
        "version_from_tag": lambda tag: tag.removeprefix("v"),
        "assets": {
            "x86_64-linux": "pi-linux-x64.tar.gz",
            "aarch64-linux": "pi-linux-arm64.tar.gz",
            "aarch64-darwin": "pi-darwin-arm64.tar.gz",
        },
        "url": lambda version, asset: f"https://github.com/earendil-works/pi/releases/download/v{version}/{asset}",
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


def latest_github_release(config):
    releases = json.loads(fetch_text(config["release_api"], token=os.environ.get("GH_TOKEN")))
    tag_pattern = re.compile(config["tag_pattern"])

    for release in releases:
        tag = release.get("tag_name", "")
        if not tag_pattern.match(tag):
            continue
        version = config["version_from_tag"](tag)
        required_assets = {asset.format(version=version) for asset in config["assets"].values()}
        assets = {asset["name"] for asset in release.get("assets", [])}
        if required_assets <= assets:
            return version

    raise RuntimeError(f"could not find a release with all required assets for {config['path'].name}")


def latest_cursor_cli():
    script = fetch_text("https://cursor.com/install", user_agent="curl/8.0")
    match = re.search(
        r"https://downloads\.cursor\.com/lab/([^/]+)/\$\{OS\}/\$\{ARCH\}/agent-cli-package\.tar\.gz",
        script,
    )
    if not match:
        raise RuntimeError("could not find Cursor CLI version in install script")
    return match.group(1)


def latest_antigravity(config):
    releases = set()

    for manifest in config["manifests"].values():
        data = json.loads(
            fetch_text(
                f"{config['manifest_base']}/manifests/{manifest}.json",
                user_agent="curl/8.0",
            )
        )
        match = re.search(r"/antigravity-cli/([^/]+)/", data.get("url", ""))
        if not match:
            raise RuntimeError(f"could not find Antigravity release in {manifest} manifest")
        releases.add(match.group(1))

    if len(releases) != 1:
        raise RuntimeError(f"Antigravity manifests disagree on release: {', '.join(sorted(releases))}")

    return releases.pop()


def latest_version(name, config):
    if name == "antigravity-cli":
        return latest_antigravity(config)
    if "release_api" in config:
        return latest_github_release(config)
    if name == "cursor-cli":
        return latest_cursor_cli()
    raise RuntimeError(f"unsupported package: {name}")


def prefetch_hash(url):
    output = subprocess.check_output(["nix", "store", "prefetch-file", "--json", url], text=True)
    return json.loads(output)["hash"]


def update_package(name, config, version):
    if config.get("nix_update"):
        subprocess.run(
            [
                "nix",
                "run",
                "nixpkgs#nix-update",
                "--",
                "--flake",
                name,
                "--version",
                version,
            ],
            cwd=ROOT,
            check=True,
        )
        return

    path = config["path"]
    text = path.read_text()
    text, count = re.subn(r'version = "[^"]+";', f'version = "{version}";', text, count=1)
    if count != 1:
        raise RuntimeError(f"failed to update version in {path}")

    for system, asset in config["assets"].items():
        hash_value = prefetch_hash(config["url"](version, asset))
        pattern = (
            rf"({re.escape(system)} = \{{\n"
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
            if "\n" in value:
                print(f"{name}<<__GITHUB_OUTPUT_EOF__", file=output)
                print(value, file=output)
                print("__GITHUB_OUTPUT_EOF__", file=output)
            else:
                print(f"{name}={value}", file=output)
    else:
        print(f"{name}={value}")


def format_summary(name, current, latest):
    return f"{name}: {current} -> {latest}"


def commit_subject(changes):
    if len(changes) == 1:
        name, _, latest = changes[0]
        return f"chore(pkgs): bump {name} to {latest}"

    details = ", ".join(f"{name} {latest}" for name, _, latest in changes)
    return f"chore(pkgs): bump CLI packages ({details})"


def commit_body(changes):
    return "\n".join(f"- {format_summary(name, current, latest)}" for name, current, latest in changes)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", default="all", choices=["all", *PACKAGES])
    parser.add_argument("--version", default="")
    args = parser.parse_args()

    selected = [name for name in PACKAGES if name not in AUTO_BUMP_SKIP] if args.package == "all" else [args.package]
    if args.version and len(selected) != 1:
        raise SystemExit("--version requires selecting one package")

    changed = []
    summaries = []

    for name in selected:
        config = PACKAGES[name]
        current = current_version(config["path"])
        latest = args.version or latest_version(name, config)
        summaries.append(format_summary(name, current, latest))

        if current == latest:
            continue

        update_package(name, config, latest)
        changed.append((name, current, latest))

    set_output("changed", "true" if changed else "false")
    set_output(
        "files",
        " ".join(str(PACKAGES[name]["path"].relative_to(ROOT)) for name, _, _ in changed),
    )
    set_output("summary", "; ".join(summaries))
    set_output("commit_subject", commit_subject(changed) if changed else "")
    set_output("commit_body", commit_body(changed) if changed else "")

    for summary in summaries:
        print(summary)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
