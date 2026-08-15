# Google NixOS migration review decisions

Date: 2026-08-15

Status: implemented and verified. Oracle2 rollout is deferred while another agent runs a backup experiment there.

## Scope

This records the simplification review following the Google NixOS migration. The goal is to keep shared modules import-driven, remove repeated host configuration, and make their operational responsibilities complete.

## Decisions

### Complete the Tailscale exit-node responsibility

`tailscale-gnet.nix` currently advertises an exit node while disabling Tailscale netfilter and SNAT:

- `--advertise-exit-node`
- `--netfilter-mode=off`
- `--snat-subnet-routes=false`

The corresponding NAT is still implemented independently by some hosts. Google, Oracle2, and somo-gw have no equivalent generic rule, so advertising an exit does not by itself guarantee a working exit datapath.

Keep topology-specific NAT on routers such as cjia, el, el2, and the SOMO routers. Put the ordinary single-WAN VM implementation behind a shared import-only module and use it for Google, blog, do, misc0-jp, Oracle2, somo-gw, and xtom where applicable. The module should own the generic Tailscale egress masquerade rule; do should retain its unrelated DNAT behavior.

Do not add a public option merely to select NAT variants. Separate import-only modules are clearer than a shallow configuration interface.

### Use one source of truth for Tailscale flags

Callers currently repeat the same additions in `extraUpFlags` and `extraSetFlags`. Make the effective `extraUpFlags` the source of truth and derive `extraSetFlags` from it in the shared module. Callers should append host-specific route flags only once.

Verify that the evaluated lists remain identical for cjia, el, el2, somo-minisforum, and somo-nanopi-r4s.

### Make unattended Tailscale enrollment complete

The shared `authKeyFile = lib.mkDefault "/run/agenix/tailscale-auth-key"` is intentional and should remain. The shared module should also declare the matching common agenix secret when that default path is used. A new caller should not need to know the hidden requirement to declare the secret separately.

Hosts using a distinct key and runtime path, such as the two SOMO machines, should continue to override the default. Remove redundant `authKeyFile` and common-secret declarations from hosts after the shared module owns them.

### Add an import-only Nylon public-exit module

Extract the repeated public Nylon exit configuration into `nixos/optional/nylon-public-exit.nix`. It should import `nylon.nix` and contain the repository's fixed public-exit behavior without exposing new options:

- enable Nylon;
- use overlay subnets `10.250.10.0/24` and `fd10:250:10::/64`;
- disable overlay NAT;
- assign label 100 to the public exit.

Use it from Google, blog, do, Oracle2, and the shared xtom configuration. do and Oracle2 should continue adding their Cloudflare WARP exit locally.

### Collapse the shallow Google services module

After extracting the shared Nylon behavior, `nixos/hosts/google/services.nix` would contain only the journald limit. Move that setting into `default.nix` and delete the one-use module.

Also remove `boot.loader.efi.canTouchEfiVariables = false`; it is already the NixOS default.

### Remove the public Nylon route-batch interface

Fix this in the same implementation. `services.nylon.routeBatch` exposes `enable`, `dir`, `ipv4File`, and `ipv6File`, but no caller overrides the paths. Current usage also shows that route batches are not an independent capability: policy-routing nodes need them, while exit-only nodes explicitly disable them.

Remove the entire public `routeBatch` option set. Inside `nylon.nix`:

- keep `/var/lib/nylon/policy-routing` as a private implementation path;
- derive `routes4.batch`, `routes6.batch`, `rules4.batch`, and `rules6.batch` from that path internally;
- create the files and enable `nylon-routes.service` when `services.nylon.policyRouting.enable` is true;
- remove the assertion coupling `policyRouting.enable` to `routeBatch.enable` because the invalid state will no longer be representable;
- make `networking.policyRouting` consume the private rule-file paths directly.

Remove every host-level `routeBatch.enable = false`. The new `nylon-public-exit.nix` should not mention route batches: their absence follows naturally from `policyRouting.enable = false`.

## Verification

1. Run `git add -N` for each new Nix file before evaluation.
2. Run `just fmt`, `just check`, and `git diff --check`.
3. Evaluate Tailscale auth paths and final up/set flags for every `tailscale-gnet` caller.
4. Evaluate every caller of the new Nylon public-exit module.
5. Verify `nylon-routes.service` and policy rule files exist on policy-routing nodes and remain absent on exit-only nodes.
6. Deploy Google first and confirm Tailscale, Nylon, PowerDNS, and Lightning Stream remain healthy.
7. Test actual IPv4 and IPv6 forwarding through Google as a Tailscale exit node; service activation alone is insufficient to verify NAT.
8. Roll the shared NAT change out to the remaining simple VM exits, while checking that router-specific NAT remains unchanged.

## Results

- `just fmt`, `just check`, and `git diff --check` pass.
- Evaluated Tailscale `extraUpFlags` and `extraSetFlags` are identical for every caller.
- Policy-routing nodes retain `nylon-routes.service`; exit-only nodes do not generate it.
- Google, blog, do, misc0-jp, somo-gw, and the three xtom hosts run the shared VM exit NAT. Router-specific NAT is unchanged.
- Google runs Tailscale, Nylon, PowerDNS, Lightning Stream, and nftables without failed units.
- Through Google as a Tailscale exit, IPv4 egress is `35.230.71.90` and IPv6 egress is `2600:1900:4041:772::`.
