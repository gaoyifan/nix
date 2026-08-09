# Tailscale settings shared by GNet routers and exit nodes.
{
  config,
  lib,
  ...
}: let
  gnetFlags = [
    "--accept-dns=false"
    "--accept-routes"
    "--advertise-exit-node"
    "--netfilter-mode=off"
    "--operator=yifan"
    "--snat-subnet-routes=false"
  ];
in {
  imports = [./policy-routing.nix];

  networking.policyRouting = {
    ipv4.rules = lib.mkBefore ["pref 110 lookup 52 suppress_prefixlength 0"];
    ipv6.rules = lib.mkBefore ["pref 110 lookup 52 suppress_prefixlength 0"];
  };

  services.tailscale = {
    enable = true;
    authKeyFile = lib.mkDefault "/run/agenix/tailscale-auth-key";
    useRoutingFeatures = "server";
    extraUpFlags = gnetFlags;
    extraSetFlags = gnetFlags;
  };
}
