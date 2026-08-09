{lib, ...}: let
  routeFlags = ["--advertise-routes=100.65.1.0/24"];
in {
  imports = [../../optional/tailscale-gnet.nix];

  services.tailscale = {
    authKeyFile = lib.mkForce null;
    port = 6627;
    extraUpFlags = routeFlags;
    extraSetFlags = routeFlags;
  };
}
