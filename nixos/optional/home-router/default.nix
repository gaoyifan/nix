{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter;
in {
  imports = [
    ../edge-firewall.nix
    ../policy-routing.nix
    ./options.nix
    ./diverge.nix
    ./networkd.nix
    ./firewall.nix
    ./services.nix
    ./monitoring.nix
    ./wlt.nix
    ./wg-iplc.nix
  ];

  config = lib.mkIf cfg.enable {
    boot.kernelModules = ["br_netfilter"];
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-arptables" = 0;
      "net.bridge.bridge-nf-call-iptables" = 0;
      "net.bridge.bridge-nf-call-ip6tables" = 0;
    };

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
    networking.edgeFirewall.enable = true;
    networking.firewall.enable = false;
    networking.nftables.enable = true;
    networking.nftables.flushRuleset = false;
    networking.nftables.tables.home-router = {
      family = "inet";
      content = ''
        chain mss-forward {
          type filter hook forward priority mangle; policy accept;
          tcp flags syn tcp option maxseg size set rt mtu
        }
      '';
    };
    networking.policyRouting.enable = true;

    boot.kernel.sysctl = {
      "net.ipv4.conf.*.rp_filter" = 0;
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv6.conf.all.forwarding" = true;
    };

    systemd.network.config.networkConfig.ManageForeignRoutes = false;
  };
}
