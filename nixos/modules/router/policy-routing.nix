# Policy routing configuration
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.router;
  wg = cfg.wgWan;
  pr = cfg.policyRouting;
in
  lib.mkIf wg.enable {
    # Custom routing table name
    environment.etc."iproute2/rt_tables.d/router.conf".text = ''
      ${toString wg.routeTable} wgwan
    '';

    # Policy routing rules via systemd-networkd
    systemd.network.networks."10-lan".routingPolicyRules = [
      {
        FirewallMark = pr.wgMark;
        Table = wg.routeTable;
        Priority = 100;
      }
      {
        FirewallMark = wg.fwMark;
        Table = "main";
        Priority = 50;
      }
    ];
  }
