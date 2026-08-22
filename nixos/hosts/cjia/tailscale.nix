{...}: let
  routeFlags = ["--advertise-routes=100.65.1.0/24"];
in {
  imports = [../../optional/tailscale-gnet.nix];

  services.tailscale = {
    extraUpFlags = routeFlags;
  };
}
