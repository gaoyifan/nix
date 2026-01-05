# Tailscale configuration
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.router;
  secrets = config.services.secrets.nixos.${config.networking.hostName};
in
  lib.mkIf cfg.tailscale.enable {
    services.tailscale = {
      enable = true;
      openFirewall = false;
      authKeyFile = secrets.tailscale.authKeyFile;

      extraSetFlags = [
        "--netfilter-mode=off"
        "--accept-routes=false"
      ];

      extraUpFlags = lib.flatten [
        "--reset"
        "--accept-routes=false"
        "--accept-dns=false"
        (lib.optional (cfg.tailscale.advertiseRoutes != [])
          "--advertise-routes=${lib.concatStringsSep "," cfg.tailscale.advertiseRoutes}")
      ];

      useRoutingFeatures = "none";
    };

    # Tailscale interface network configuration
    systemd.network.networks."60-tailscale" = {
      matchConfig.Name = "tailscale*";
      networkConfig.DHCP = "no";
      linkConfig.RequiredForOnline = "no";
    };
  }
