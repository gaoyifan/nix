# Home Router monitoring: agent notes

Entry point: [`monitoring/default.nix`](../nixos/optional/home-router/monitoring/default.nix).

Preserve these invariants when changing the implementation:

- Keep the collector resident. NanoPi R5C median collection times: CLI/Python
  oneshot ~498 ms; resident socket-based collection ~76 ms. Synthetic counters,
  live Tailscale metadata; do not interpret these as throughput benchmarks.
- Count LAN traffic once on VLAN interfaces. Ingress uses source MAC; egress uses
  destination MAC after Ethernet headers are rebuilt. VLAN egress counters include
  14 Ethernet bytes per counted skb; ingress/L3 counters do not. Recheck if moving hooks.
- Keep display names out of counter labels. Retain separate VPN address counters and apply
  `rate`/`increase` before summing by device, otherwise address expiry corrupts history.
- Missing naming services are normal; do not block counters or order against name providers.
  Actual API/collection errors preserve the old file. Check textfile mtime for staleness.
- Counters cover router-visible traffic, including routed LAN transfers and router
  services. Same-LAN switching and paths bypassing these hooks are not observable.

Verification: `just fmt`, `just check`,
`nix build --no-link .#checks.x86_64-linux.home-router`.
