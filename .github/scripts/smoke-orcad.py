#!/usr/bin/env python3
import argparse
import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path


def wait_for_pairing(server, log):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline and server.poll() is None:
        for line in log.read_text().splitlines():
            if '"type":"orca_server_ready"' in line:
                ready = json.loads(line)
                if ready["boundEndpoint"].startswith("ws://127.0.0.1:"):
                    return ready["pairing"]["url"]
                raise RuntimeError("Orcad did not bind to loopback")
        time.sleep(0.2)
    raise RuntimeError(f"Orcad did not report readiness (exit status: {server.poll()})")


def smoke(package, version, directory):
    cli = package / "bin/orca-ide"
    project = directory / "project"
    project.mkdir()
    subprocess.run(["git", "init", "--quiet", project], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            project,
            "-c",
            "user.name=Orcad smoke test",
            "-c",
            "user.email=smoke@example.invalid",
            "commit",
            "--quiet",
            "--allow-empty",
            "-m",
            "Initialize smoke test",
        ],
        check=True,
    )
    env = {**os.environ, "ORCA_TELEMETRY_DISABLED": "1"}
    client_env = {**env, "ORCA_USER_DATA_PATH": str(directory / "client")}
    actual = subprocess.check_output([cli, "--version"], env=client_env, text=True, timeout=15).strip()
    if actual != version:
        raise RuntimeError(f"expected Orca {version}, got {actual}")

    server_env = {**env, "ORCA_USER_DATA_PATH": str(directory / "server")}
    log_path = directory / "server.log"
    with log_path.open("w") as log:
        server = subprocess.Popen(
            [package / "bin/orcad", "--port", "0", "--project-root", project, "--json"],
            env=server_env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    try:
        pairing = wait_for_pairing(server, log_path)

        def paired(*args):
            result = subprocess.run(
                [cli, "--pairing-code", pairing, *args, "--json"],
                cwd=project,
                env=client_env,
                capture_output=True,
                text=True,
                timeout=20,
            )
            if result.returncode:
                detail = result.stderr.strip() or result.stdout.strip()
                raise RuntimeError(
                    f"Orca {args[0]} exited {result.returncode}: {detail.replace(pairing, '[redacted]')}"
                )
            return json.loads(result.stdout)["result"]

        runtime = paired("status")["runtime"]
        if runtime["state"] != "ready" or runtime.get("reachable") is False:
            raise RuntimeError("paired client could not reach the ready runtime")
        print(f"Orca {version} started on loopback and paired", flush=True)

        paired("repo", "add", "--path", project)
        terminal = paired(
            "terminal",
            "create",
            "--worktree",
            f"path:{project}",
            "--command",
            "printf '%s%s\\n' orcad- smoke-ok",
        )["terminal"]["handle"]
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            output = paired("terminal", "read", "--terminal", terminal)["terminal"]["tail"]
            if any(line.strip() == "orcad-smoke-ok" for line in output):
                print("Orcad terminal command returned its expected output")
                break
            time.sleep(0.2)
        else:
            raise RuntimeError("Orcad terminal did not return the smoke-test marker")
        paired("terminal", "close", "--terminal", terminal)
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid, signal.SIGKILL)
                server.wait()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("version")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="orcad-smoke-") as directory:
        smoke(args.package, args.version, Path(directory))


if __name__ == "__main__":
    main()
