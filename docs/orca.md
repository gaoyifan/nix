# Orca on el2 and nixos-orbstack

el2 runs the official Orca server bundle as `yifan`. Connect the MacBook's Orca
desktop app to `wss://orcad.ts.gaof.net` through Tailscale Serve. Orcad uses its
default loopback listener (`127.0.0.1:6768`); the `orcad` Tailscale Service
terminates TLS on port 443 using the existing ACME certificate and forwards
WebSocket connections to it. No host Tailscale IP is pinned, and no Orca Cloud
relay, Electron, or Xvfb is involved.

`nixos-orbstack` runs the same service with a native ARM64 package. Its separate
Tailscale Service is `orcad-orbstack`, at `wss://orcad-orbstack.ts.gaof.net`.
Both hosts pull the shared ACME certificates and refresh Tailscale Serve when
certificates change. The `orcad-orbstack` Service has endpoint `tcp:443` and
`nixos-orbstack` is approved as its service host. The encrypted Tailscale management
key is `secrets/files/nixos/el2/tailscale-api-key.age`; it can manage Service
creation and host approval without a browser. Keep decrypted keys out of the Nix
store and command output. The existing DNS syncer publishes the Service VIP in
`ts.gaof.net`; resolvers can cache an earlier NXDOMAIN response for five minutes.

The deployment was verified from the Mac's bundled Orca CLI through the hostname:
TLS validation, paired runtime status, worktree creation, and a terminal command
round trip all passed. The temporary terminal and worktree were removed afterward.

## Pair the MacBook

On the host to pair, retrieve the latest startup pairing link:

```sh
sudo journalctl -u orcad -b -o cat --no-pager |
  jq -Rr 'fromjson? | select(.type == "orca_server_ready") | .pairing.url' |
  tail -n 1
```

In the MacBook's Orca app, choose **Add remote server** and paste the complete
`orca://pair?...` link. It contains a device credential; keep it private. Choose
the existing server pairing flow rather than installing another runtime over SSH.

## Shared configuration

Import `nixos/optional/orcad.nix` to enable the runtime, Tailscale TLS ingress, and
shared ACME certificates. The only host-specific option is
`services.orcad.tailscaleServiceName`, which defaults to `orcad`; OrbStack uses
`orcad-orbstack`. The public hostname is `<service-name>.ts.gaof.net`.
The ACME module owns its secret declaration and uses the host's chosen resolver.

## State and maintenance

- Runtime state and pairing keys: `/var/lib/orca`, owned by `yifan:users`, mode `0700`.
- Codex uses `/home/yifan/.codex`, which links to the existing
  `/home/yifan/.syncd-dotfiles/.codex` configuration. Keep `CODEX_HOME` spelled as
  `~/.codex`: Orca compares paths without resolving symlinks and treats the
  `.syncd-dotfiles` path as a custom home, selecting its legacy managed mirror.
  On el2, importing history into that mirror falls back to symlinks because
  `/var/lib/orca` and `/home` are on different filesystems; Codex fork rejects
  those external rollout paths. New system-default launches use the original
  home directly; already-running Codex processes retain their previous home.
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
The package exposes the bundled `orca-ide` CLI and an `orcad` launcher that runs
`orca-ide serve` on loopback.
Disconnecting the MacBook leaves agents running. Restarting the systemd service
briefly disconnects clients; daemon-backed terminals and CLI agents survive when
the daemon runs in a separate user scope with linger enabled and the incoming
version supports its protocol. In-process sessions do not survive. Keep the old
daemon's bundle and runtime available while it is live.
The server tarball hashes for both Linux architectures are pinned in `pkgs/orcad.nix`.
Deploy changes with `just nixos` on the target host. Deployment leaves the running version unchanged
(`restartIfChanged = false`); activate the installed version with
`sudo systemctl restart orcad`.

The upstream bundle includes Node, the PTY addon, the native watcher, and the
mobile web client. The Nix launcher uses `nix-ld` on NixOS so the files keep the
byte-level identities Orca checks at startup.

The independent **Bump Orcad** workflow waits for both server tarballs and their
checksum manifest on a stable GitHub release. It builds the exact candidate on
x86_64 and ARM64, starts an isolated server, pairs a CLI client, and checks a
terminal command on each architecture before pushing the pin. A failed candidate
leaves the current pin in place. Use the workflow's `version` input to select a
specific stable release.
