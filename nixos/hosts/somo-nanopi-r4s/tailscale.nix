{
  config,
  lib,
  ...
}: let
  routeFlags = ["--advertise-routes=100.65.12.0/24,100.65.13.0/24"];
in {
  imports = [../../optional/tailscale-gnet.nix];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    somo-nanopi-r4s-tailscale-auth-key.file = config.services.secrets.filesDir + "/nixos/somo-nanopi-r4s/tailscale-auth-key.age";
  };

  services.tailscale = {
    authKeyFile = "/run/agenix/somo-nanopi-r4s-tailscale-auth-key";
    extraUpFlags = routeFlags;
  };
}
