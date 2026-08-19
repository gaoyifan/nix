# Shared edge datapath for the el and el2 routers.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.elRouter;
  homeRouter = config.networking.homeRouter;
  types = lib.types;

  addressWithoutPrefix = address: lib.head (lib.splitString "/" address);
  ipv4Addresses = addresses: lib.filter (address: !(lib.hasInfix ":" address)) addresses;
  ipv6Addresses = addresses: lib.filter (address: lib.hasInfix ":" address) addresses;

  cernet = homeRouter.wans.cernet;
  chinanet = homeRouter.wans.chinanet;
  cmcc = homeRouter.wans.cmcc;
  cernetInterface = cernet.interface;
  chinanetInterface = chinanet.interface;
  cmccInterface = cmcc.interface;
  cernetIpv4 = addressWithoutPrefix (lib.head (ipv4Addresses cernet.addresses));
  cernetIpv6 = addressWithoutPrefix (lib.head (ipv6Addresses cernet.addresses));
  chinanetIpv4 = addressWithoutPrefix (lib.head (ipv4Addresses chinanet.addresses));
  cmccIpv4 = addressWithoutPrefix (lib.head (ipv4Addresses cmcc.addresses));
  cernetMark = toString cernet.routingTable;
  chinanetMark = toString chinanet.routingTable;
  cmccMark = toString cmcc.routingTable;
  preservedUdpSourcePorts = [
    2197
    config.services.nylon.udpPort
    6627
  ];

  nftSet = values: lib.concatMapStringsSep ", " toString values;
  returnSourceRules = lib.concatMapStringsSep "\n" (address: "ip saddr ${address} return") cfg.unclassifiedIpv4Sources;
  masqueradeRules = lib.concatMapStringsSep "\n" (interface: ''oifname "${interface}" masquerade'') cfg.masqueradeInterfaces;
in {
  imports = [
    ./edge-firewall.nix
    ./nylon.nix
  ];

  options.networking.elRouter = {
    enable = lib.mkEnableOption "shared GNet multi-WAN edge datapath";

    unclassifiedIpv4Sources = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "IPv4 source addresses left to source-policy routing before destination classification.";
    };

    masqueradeInterfaces = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional interfaces requiring source masquerade.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (name: lib.hasAttr name homeRouter.wans) [
          "cernet"
          "chinanet"
          "cmcc"
        ];
        message = "networking.elRouter requires cernet, chinanet, and cmcc homeRouter WANs.";
      }
      {
        assertion = ipv4Addresses cernet.addresses != [] && ipv6Addresses cernet.addresses != [];
        message = "networking.elRouter requires CERNET IPv4 and IPv6 addresses.";
      }
      {
        assertion = ipv4Addresses chinanet.addresses != [] && ipv4Addresses cmcc.addresses != [];
        message = "networking.elRouter requires China Telecom and China Mobile IPv4 addresses.";
      }
      {
        assertion = lib.all (wan: wan.routingTable != null) [
          cernet
          chinanet
          cmcc
        ];
        message = "networking.elRouter requires dedicated routing tables for all WANs.";
      }
    ];

    networking.homeRouter.wgIplc.enable = true;
    networking.wireguard.interfaces.wg-iplc.fwMark = lib.mkForce chinanetMark;

    services.nylon = {
      enable = true;
      policyRouting.enable = true;
      exits = {
        cernet = {
          label = 100;
          interface = cernetInterface;
          gateway4 = cernet.gateway4;
          ipv4Address = cernetIpv4;
          ipv6Address = cernetIpv6;
        };
        chinanet = {
          label = 101;
          interface = chinanetInterface;
          gateway4 = chinanet.gateway4;
          ipv4Address = chinanetIpv4;
        };
        cmcc = {
          label = 102;
          interface = cmccInterface;
          gateway4 = cmcc.gateway4;
          ipv4Address = cmccIpv4;
        };
      };
    };

    networking.edgeFirewall.enable = true;

    networking.nftables.tables = {
      el-router = {
        family = "inet";
        content = ''
          include "${pkgs.nft-geo-sets}/set-cn.conf"
          include "${pkgs.nft-geo-sets}/set-cn6.conf"
          include "${pkgs.nft-geo-sets}/set-cernet.conf"
          include "${pkgs.nft-geo-sets}/set-chinanet.conf"
          include "${pkgs.nft-geo-sets}/set-cmcc.conf"

          chain classify {
            meta mark != 0 return
            ${returnSourceRules}
            udp sport { ${nftSet preservedUdpSourcePorts} } return

            ip saddr ${chinanetIpv4} meta mark set ${chinanetMark} return
            ip saddr ${cmccIpv4} meta mark set ${cmccMark} return

            ip daddr @cernet meta mark set ${cernetMark} return
            ip daddr @chinanet meta mark set ${chinanetMark} return
            ip daddr @cmcc meta mark set ${cmccMark} return
            ip daddr @cn meta mark set ${chinanetMark} return
            meta nfproto ipv4 meta mark set ${homeRouter.wgIplc.mark} return

            ip6 daddr @cn6 meta mark set ${cernetMark} return
            ip6 daddr != @cn6 meta l4proto ipv6-icmp return
            ip6 daddr != @cn6 reject with icmpx type admin-prohibited
          }

          chain prerouting {
            type filter hook prerouting priority mangle + 1; policy accept;
            jump classify
          }

          chain output {
            type route hook output priority mangle + 1; policy accept;
            jump classify
          }

          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ${masqueradeRules}
            meta mark ${homeRouter.wgIplc.mark} oifname "wg-iplc" masquerade
            meta mark ${cernetMark} oifname "${cernetInterface}" snat ip to ${cernetIpv4}
            meta mark ${chinanetMark} oifname "${chinanetInterface}" snat ip to ${chinanetIpv4}
            meta mark ${cmccMark} oifname "${cmccInterface}" snat ip to ${cmccIpv4}
          }
        '';
      };
    };
  };
}
