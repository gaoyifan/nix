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
    "--snat-subnet-routes=false"
  ];
in {
  services.tailscale = {
    enable = true;
    authKeyFile = lib.mkDefault config.services.secrets.nixos.tailscale.authKeyFile;
    useRoutingFeatures = "server";
    extraUpFlags = gnetFlags;
    extraSetFlags = gnetFlags;
  };
}
