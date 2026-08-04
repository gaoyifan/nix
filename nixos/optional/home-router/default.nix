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
  ];

  config = lib.mkIf cfg.enable {
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
