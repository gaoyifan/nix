# Orca on el2

el2 runs the plain Node `orcad` runtime as `yifan`. Connect the MacBook's Orca
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

Run the management CLI from this checkout:

```sh
nix shell .#nixosConfigurations.el2.pkgs.orcad -c \
  env ORCA_USER_DATA_PATH=/var/lib/orca orca-ide status --json
```

Replace `status` with `terminal list` to inspect active terminals before maintenance.
Disconnecting the MacBook leaves agents running. Restarting the systemd service
ends its terminals and agents, so finish those tasks before an upgrade or restart.
The runtime and dependency hashes are pinned in `pkgs/orcad.nix`; deploy changes
with `just nixos` from el2.

The package runs upstream's Node-only bundle checks and compiles the CLI. Deployment
validation also exercises native file watching, PTY output, authenticated worktree
operations, unauthenticated connection rejection, and a Codex file-writing task
whose client disconnects before completion.
