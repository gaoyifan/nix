# Tailscale settings shared by GNet routers and exit nodes.
{
  config,
  lib,
  ...
}: let
  overlayRule = "lookup 52 suppress_prefixlength 0";
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

  age.secrets =
    lib.mkIf (
      config.services.secrets.hasRealFiles
      && config.services.tailscale.authKeyFile == "/run/agenix/tailscale-auth-key"
    ) {
      tailscale-auth-key.file = config.services.secrets.filesDir + "/nixos/tailscale-auth-key.age";
    };

  networking.policyRouting = {
    ipv4.routingPolicyRules.postMain = lib.mkBefore [overlayRule];
    ipv6.routingPolicyRules.postMain = lib.mkBefore [overlayRule];
  };

  services.tailscale = {
    enable = true;
    authKeyFile = lib.mkDefault "/run/agenix/tailscale-auth-key";
    useRoutingFeatures = "server";
    extraUpFlags = gnetFlags;
    extraSetFlags = config.services.tailscale.extraUpFlags;
  };
}
