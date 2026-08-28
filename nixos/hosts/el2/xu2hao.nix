{config, ...}: let
  homeRouter = config.networking.homeRouter;
  chinanetInterface = homeRouter.wans.chinanet.interface;
  chinanetMark = toString homeRouter.wans.chinanet.routingTable;
in {
  networking.edgeFirewall.extraForwardRules = ["ct status dnat accept"];

  networking.nftables.tables.xuhao = {
    family = "inet";
    content = ''
      chain prerouting-dnat {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "${chinanetInterface}" ip daddr 202.141.162.72 meta l4proto { tcp, udp } th dport 10300 dnat ip to 100.64.2.30
      }

      chain force-chinanet {
        type filter hook prerouting priority mangle + 2; policy accept;
        ${homeRouter.wlt.dns.frontDoorBypassRules}
        ip saddr 100.64.2.30 meta mark set ${chinanetMark}
      }

      chain block-gnet {
        type filter hook forward priority filter - 1; policy accept;
        ip saddr 100.64.2.30 ip daddr 100.64.0.0/10 ct state new drop
      }
    '';
  };
}
