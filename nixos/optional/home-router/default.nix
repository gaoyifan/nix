{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter;
in {
  imports = [
    ../policy-routing.nix
    ./options.nix
    ./networkd.nix
    ./firewall.nix
    ./services.nix
    ./monitoring.nix
    ./wlt.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !cfg.monitoring.enable
          || (cfg.monitoring.wans != [] && lib.all (wan: lib.hasAttr wan cfg.wans) cfg.monitoring.wans);
        message = "networking.homeRouter.monitoring.wans must name at least one configured WAN when monitoring is enabled.";
      }
    ];

    networking.useDHCP = false;
    networking.useNetworkd = true;
    networking.firewall.enable = false;
    networking.nftables.enable = true;
    networking.nftables.flushRuleset = false;

    boot.kernel.sysctl = {
      "net.ipv4.conf.*.rp_filter" = 0;
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv6.conf.all.forwarding" = true;
    };

    systemd.network.config.networkConfig = {
      ManageForeignRoutes = false;
      ManageForeignRoutingPolicyRules = false;
    };
  };
}
