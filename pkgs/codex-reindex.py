#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["jsonrpcclient==4.0.3"]
# ///

import argparse
import json
import os
import subprocess
import sys

from jsonrpcclient import Error, Ok, notification, parse, request

CODEX = os.environ["CODEX_REINDEX_CODEX"]
SOURCE_KINDS = [
    "cli",
    "vscode",
    "exec",
    "appServer",
    "subAgent",
    "subAgentReview",
    "subAgentCompact",
    "subAgentThreadSpawn",
    "subAgentOther",
    "unknown",
]


def main():
    parser = argparse.ArgumentParser(description="Reindex Codex JSONL sessions into the local state database.")
    parser.add_argument("--version", action="version", version="codex-reindex 1")
    parser.parse_args()

    process = subprocess.Popen(
        [CODEX, "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )

    def send(message):
        process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        process.stdin.flush()

    def rpc(method, params):
        message = request(method, params=params)
        send(message)

        for line in process.stdout:
            response = json.loads(line)
            if response.get("id") != message["id"]:
                continue
            match parse(response):
                case Ok(result, _):
                    return result
                case Error(_, error_message, _, _):
                    raise RuntimeError(f"{method}: {error_message}")
        raise RuntimeError(f"app-server exited before responding to {method}")

    def reindex(archived):
        cursor = None
        total = 0
        while True:
            params = {
                "limit": 100,
                "sortKey": "created_at",
                "sortDirection": "desc",
                "modelProviders": [],
                "sourceKinds": SOURCE_KINDS,
                "archived": archived,
                "useStateDbOnly": False,
            }
            if cursor is not None:
                params["cursor"] = cursor

            result = rpc("thread/list", params)
            total += len(result["data"])
            cursor = result.get("nextCursor")
            label = "archived" if archived else "active"
            print(f"\rFound {total} {label} sessions", end="", flush=True)
            if cursor is None:
                print()
                return total

    try:
        rpc(
            "initialize",
            {
                "clientInfo": {
                    "name": "codex_reindex",
                    "title": "Codex session reindex",
                    "version": "1",
                }
            },
        )
        send(notification("initialized", params={}))
        active = reindex(False)
        archived = reindex(True)

        process.stdin.close()
        return_code = process.wait()
        if return_code != 0:
            raise RuntimeError(f"app-server exited with status {return_code}")
    except BaseException:
        if process.poll() is None:
            process.terminate()
        process.wait()
        raise

    print(f"Reindex complete: found {active} active, {archived} archived sessions.")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, ValueError) as error:
        print(f"codex-reindex: {error}", file=sys.stderr)
        raise SystemExit(1)
