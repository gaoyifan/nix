# Orca on el2

el2 runs `orcad` directly with its pinned Bun runtime as `yifan`. Connect the MacBook's Orca
desktop app to `wss://orcad.ts.gaof.net` through Tailscale Serve. Orcad uses its
default loopback listener (`127.0.0.1:6768`); the `orcad` Tailscale Service
terminates TLS on port 443 using the existing ACME certificate and forwards
WebSocket connections to it. No host Tailscale IP is pinned, and no Orca Cloud
relay, Electron, or Xvfb is involved.

## Pair the MacBook

On el2, retrieve the latest startup pairing link:

```sh
sudo journalctl -u orcad -b -o cat --no-pager |
  jq -Rr 'fromjson? | select(.type == "orca_server_ready") | .pairing.url' |
  tail -n 1
```

In the MacBook's Orca app, choose **Add remote server** and paste the complete
`orca://pair?...` link. It contains a device credential; keep it private. Choose
the existing server pairing flow rather than installing another runtime over SSH.

## State and maintenance

- Runtime state and pairing keys: `/var/lib/orca`, owned by `yifan:users`, mode `0700`.
- Codex uses the existing `/home/yifan/.syncd-dotfiles/.codex` configuration.
- Worktrees use Orca's default `~/orca/workspaces` location unless changed in Orca.
- Telemetry is disabled. Mobile push, cloud sign-in, and cloud sharing are outside
  this deployment; use runtime pairing for the desktop client.
- Server-side browser panes and speech are not configured.

Inspect the service from this checkout:

```sh
systemctl status orcad
sudo journalctl -u orcad -b --no-pager
```

Use the desktop client to inspect active terminals before maintenance.
The package provides only `orcad`, without the separate `orca-ide` management CLI.
Disconnecting the MacBook leaves agents running. Restarting the systemd service
ends its terminals and agents, so finish those tasks before an upgrade or restart.
The runtime and dependency hashes are pinned in `pkgs/orcad.nix`; deploy changes
with `just nixos` from el2.
Scheduled updates select stable GitHub releases, rather than snapshots of `main`.
`pkgs/orcad-bun.nix` pins the Bun version required by Orcad using nixpkgs' existing
binary packaging recipe and stable dependencies. Update that pin when an Orcad
release changes its required Bun version; the upstream build checks the version.
The watcher downloader prepares an offline dependency cache covered by `pnpmDeps.hash`.

The package installs upstream's headless runtime bundle, including its workers,
native watcher and identity-tracked resources. Node and pnpm are build tools;
the service and terminal daemon run with Bun's native PTY support. The project-wide
`node_modules` tree and `node-pty` are not installed.

The build runs upstream's smoke checks and final preflight, which exercises PTY
creation, native file watching and persistence workers. Preflight also refreshes
the artifact identity after Nix's ELF fixups.

For Orcad 1.4.216 on x86_64-linux, this packaging reduced the runtime closure from
1755.8 MiB (71 store paths) to 171.6 MiB (8 paths). The result has no Node.js runtime
dependency and uses the same glibc as stdenv, eliminating the extra glibc build.
