# Tailscale for internal access only: it must not touch the host firewall
# (netfilter-mode=off) or DNS (accept-dns=false). The node advertises both
# IPv4 and IPv6 LAN prefixes and acts as an exit node.
# Traffic initiated from the untagged SOMO LAN towards the tailnet is dropped by the
# stateful filter in networking.nix; the reverse direction stays open.
{
  config,
  lib,
  ...
}: let
  routeFlags = ["--advertise-routes=100.65.2.0/24,100.65.3.0/24,fd9a:2d16:5c3e:2::/64,fd9a:2d16:5c3e:3::/64"];
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    somo-minisforum-tailscale-auth-key.file = config.services.secrets.filesDir + "/nixos/somo-minisforum/tailscale-auth-key.age";
  };

  services.tailscale = {
    authKeyFile = "/run/agenix/somo-minisforum-tailscale-auth-key";
    extraUpFlags = routeFlags;
  };
}
