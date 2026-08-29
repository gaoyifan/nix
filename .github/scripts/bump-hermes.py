#!/usr/bin/env python3
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[2]
FLAKE = ROOT / "flake.nix"
RELEASE_API = "https://api.github.com/repos/NousResearch/hermes-agent/releases/latest"
TAG_PATTERN = re.compile(r"^v[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}(?:\.[0-9]+)?$")
INPUT_PATTERN = re.compile(r'(url = "github:NousResearch/hermes-agent)(?:/([^"]+))?(";)')
EXCLUDED_TAGS = {"v2026.8.13"}


def latest_release_tag():
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "bump-hermes",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(RELEASE_API, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        tag = json.load(response)["tag_name"]

    if not TAG_PATTERN.fullmatch(tag):
        raise RuntimeError(f"unexpected Hermes release tag: {tag}")
    return tag


def current_release_tag(text):
    matches = list(INPUT_PATTERN.finditer(text))
    if len(matches) != 1:
        raise RuntimeError("could not uniquely locate the hermes-agent flake input")
    return matches[0].group(2)


def update_flake_input(text, tag):
    updated, count = INPUT_PATTERN.subn(rf"\g<1>/{tag}\g<3>", text, count=1)
    if count != 1:
        raise RuntimeError("failed to update the hermes-agent flake input")
    FLAKE.write_text(updated)


def hermes_version():
    expression = "(builtins.getFlake (toString ./.)).inputs.hermes-agent.packages.x86_64-linux.minimal.version"
    return subprocess.check_output(
        ["nix", "eval", "--raw", "--impure", "--expr", expression],
        cwd=ROOT,
        text=True,
    ).strip()


def set_output(name, value):
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a") as output:
            print(f"{name}={value}", file=output)
    else:
        print(f"{name}={value}")


def main():
    latest_tag = latest_release_tag()
    text = FLAKE.read_text()
    current_tag = current_release_tag(text)
    if latest_tag in EXCLUDED_TAGS:
        version = hermes_version()
        summary = f"Hermes: skipped excluded release {latest_tag}; staying on {current_tag} ({version})"

        set_output("changed", "false")
        set_output("files", "flake.nix flake.lock")
        set_output("commit_subject", "")
        set_output("commit_body", "")
        set_output("summary", summary)
        print(summary)
        return

    changed = current_tag != latest_tag

    if changed:
        update_flake_input(text, latest_tag)
        subprocess.run(["nix", "flake", "update", "hermes-agent"], cwd=ROOT, check=True)

    version = hermes_version()
    current = current_tag or "unpinned"
    summary = f"Hermes: {current} -> {latest_tag} ({version})"

    set_output("changed", "true" if changed else "false")
    set_output("files", "flake.nix flake.lock")
    set_output("commit_subject", f"chore(hermes): bump to {version}" if changed else "")
    set_output("commit_body", summary if changed else "")
    set_output("summary", summary)
    print(summary)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
