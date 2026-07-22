{config, ...}: let
  routeFlags = ["--advertise-routes=100.65.12.0/24,100.65.13.0/24"];
in {
  imports = [../../optional/tailscale-gnet.nix];

  services.tailscale = {
    authKeyFile = "${config.services.secrets.filesDir}/nixos/somo-nanopi-r4s/tailscale-auth-key";
    extraUpFlags = routeFlags;
    extraSetFlags = routeFlags;
  };
}
