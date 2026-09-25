# Paseo on el2

el2 runs the Paseo daemon as `yifan`. Connect a Paseo client directly to
`paseo.ts.gaof.net` on port `6767` through Tailscale Serve's TCP forwarding.
The daemon listens only on `127.0.0.1:6767`. The Paseo relay and bundled Web UI
are disabled; no desktop or mobile client runs on el2.

The connection requires the daemon password. For the first deployment, build the
package and set the password before switching the NixOS configuration:

```sh
nix build '.#nixosConfigurations.el2.config.services.paseo.package' --no-link
paseo_pkg=$(nix eval --raw '.#nixosConfigurations.el2.config.services.paseo.package.outPath')
sudo install -d -m 0700 -o yifan -g users /var/lib/paseo
sudo -u yifan env PASEO_HOME=/var/lib/paseo "$paseo_pkg/bin/paseo" daemon set-password
```

Paseo stores a password hash in `/var/lib/paseo/config.json`. Keep the password
in your password manager; it is not stored in this repository. To change it,
run the same command and restart `paseo.service` after current agent tasks finish.

The daemon uses the existing Codex configuration at
`/home/yifan/.syncd-dotfiles/.codex`. State and worktrees are under
`/var/lib/paseo`. Switching NixOS does not restart a running Paseo daemon;
restart it manually to apply a package upgrade after active agents finish.

The native NixOS `tailscale-serve.service` configuration applies the TCP mapping
and advertises `svc:paseo`; no manual `tailscale serve` command is needed. A
tailnet administrator may need to approve el2's first advertisement on the
[Tailscale Services page](https://console.tailscale.com/admin/services). After
approval, the existing PowerDNS syncer creates `paseo.ts.gaof.net` from Tailscale's
service record.

Useful checks:

```sh
systemctl status paseo
sudo journalctl -u paseo -b --no-pager
tailscale serve status --json
curl -fsS http://127.0.0.1:6767/api/health
```
