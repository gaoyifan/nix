# Shared edge datapath for the el and el2 GNet routers.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.gnetEdgeRouter;
  homeRouter = config.networking.homeRouter;
  types = lib.types;

  addressWithoutPrefix = address: lib.head (lib.splitString "/" address);
  ipv4Addresses = addresses: lib.filter (address: !(lib.hasInfix ":" address)) addresses;
  ipv6Addresses = addresses: lib.filter (address: lib.hasInfix ":" address) addresses;

  internalInterface = homeRouter.lans.${cfg.lan}.interface;
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
  wgIplcTable = config.networking.wireguard.interfaces.wg-iplc.table;
  preservedUdpSourcePorts = [
    2197
    6622
    6627
  ];

  trustedInterfaces = lib.unique (
    [
      internalInterface
      "tailscale0"
      "nylon0"
    ]
    ++ cfg.trustedInterfaces
  );
  nftSet = values: lib.concatMapStringsSep ", " toString values;
  returnSourceRules = lib.concatMapStringsSep "\n" (address: "ip saddr ${address} return") cfg.unclassifiedIpv4Sources;
  masqueradeRules = lib.concatMapStringsSep "\n" (interface: ''oifname "${interface}" masquerade'') cfg.masqueradeInterfaces;
  extraInputRules = lib.concatStringsSep "\n" cfg.extraInputRules;
  extraForwardRules = lib.concatStringsSep "\n" cfg.extraForwardRules;
in {
  imports = [./nylon.nix];

  options.networking.gnetEdgeRouter = {
    enable = lib.mkEnableOption "shared GNet multi-WAN edge datapath";

    lan = lib.mkOption {
      type = types.str;
      description = "homeRouter LAN trusted by the edge filter.";
    };

    unclassifiedIpv4Sources = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "IPv4 source addresses left to source-policy routing before destination classification.";
    };

    wgIplc = {
      mark = lib.mkOption {
        type = types.str;
        default = "0x100";
        description = "Packet mark selecting the wg-iplc route table.";
      };
    };

    trustedInterfaces = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Host-specific interfaces trusted by the input and forwarding filters.";
    };

    publicTcpPorts = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "TCP ports and ranges accepted from public interfaces.";
    };

    publicUdpPorts = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "UDP ports and ranges accepted from public interfaces.";
    };

    masqueradeInterfaces = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional interfaces requiring source masquerade.";
    };

    extraInputRules = lib.mkOption {
      type = types.listOf types.lines;
      default = [];
      description = "Host-specific nftables input rules appended after public service rules.";
    };

    extraForwardRules = lib.mkOption {
      type = types.listOf types.lines;
      default = [];
      description = "Host-specific nftables forwarding rules appended after trusted interfaces.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasAttr cfg.lan homeRouter.lans;
        message = "networking.gnetEdgeRouter.lan must name a homeRouter LAN.";
      }
      {
        assertion = lib.all (name: lib.hasAttr name homeRouter.wans) [
          "cernet"
          "chinanet"
          "cmcc"
        ];
        message = "networking.gnetEdgeRouter requires cernet, chinanet, and cmcc homeRouter WANs.";
      }
      {
        assertion = ipv4Addresses cernet.addresses != [] && ipv6Addresses cernet.addresses != [];
        message = "networking.gnetEdgeRouter requires CERNET IPv4 and IPv6 addresses.";
      }
      {
        assertion = ipv4Addresses chinanet.addresses != [] && ipv4Addresses cmcc.addresses != [];
        message = "networking.gnetEdgeRouter requires China Telecom and China Mobile IPv4 addresses.";
      }
      {
        assertion = lib.all (wan: wan.routingTable != null) [
          cernet
          chinanet
          cmcc
        ];
        message = "networking.gnetEdgeRouter requires dedicated routing tables for all WANs.";
      }
    ];

    networking.policyRouting = {
      enable = true;
      ipv4.rules =
        ["pref 200 fwmark ${cfg.wgIplc.mark}/0xffffffff lookup ${wgIplcTable}"]
        ++ [
          "pref 32766 lookup main"
          "pref 32767 lookup default"
        ];
      ipv6.rules = ["pref 32766 lookup main"];
    };

    services.nylon = {
      enable = true;
      policyRouting.enable = true;
      overlay = {
        ipv4Subnet = "10.250.10.0/24";
        ipv6Subnet = "fd10:250:10::/64";
      };
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

    networking.nftables.tables = {
      gnet-edge-egress = {
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
            meta nfproto ipv4 meta mark set ${cfg.wgIplc.mark} return

            ip6 daddr @cn6 meta mark set ${cernetMark} return
            ip6 daddr != @cn6 icmpv6 type echo-request return
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
        '';
      };

      gnet-edge-nat = {
        family = "inet";
        content = ''
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ${masqueradeRules}
            meta mark ${cfg.wgIplc.mark} oifname "wg-iplc" masquerade
            meta mark ${cernetMark} oifname "${cernetInterface}" snat ip to ${cernetIpv4}
            meta mark ${chinanetMark} oifname "${chinanetInterface}" snat ip to ${chinanetIpv4}
            meta mark ${cmccMark} oifname "${cmccInterface}" snat ip to ${cmccIpv4}
          }
        '';
      };

      gnet-edge-filter = {
        family = "inet";
        content = ''
          chain input {
            type filter hook input priority filter; policy drop;
            ct state established,related accept
            iifname "lo" accept
            ip protocol icmp accept
            ip6 nexthdr icmpv6 accept

            iifname { ${lib.concatMapStringsSep ", " (interface: ''"${interface}"'') trustedInterfaces} } accept
            ${lib.optionalString (cfg.publicTcpPorts != []) "tcp dport { ${nftSet cfg.publicTcpPorts} } accept"}
            ${lib.optionalString (cfg.publicUdpPorts != []) "udp dport { ${nftSet cfg.publicUdpPorts} } accept"}
            ${extraInputRules}
          }

          chain forward {
            type filter hook forward priority filter; policy drop;
            ct state established,related accept
            ct status dnat accept
            iifname { ${lib.concatMapStringsSep ", " (interface: ''"${interface}"'') trustedInterfaces} } accept
            ${extraForwardRules}
          }
        '';
      };
    };
  };
}
