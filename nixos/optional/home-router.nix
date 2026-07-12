{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter;
  types = lib.types;

  bridgeNames = lib.attrNames cfg.bridges;
  trunkNames = lib.attrNames cfg.trunks;
  ipv6NatRules =
    lib.concatMapStringsSep "\n" (ipv6SourceSubnet: ''
      ip6 saddr ${ipv6SourceSubnet} oifname "${cfg.wan.interface}" masquerade
    '')
    cfg.nat.ipv6SourceSubnets;

  vlanDeviceName = trunkName: vlanKey: vlanCfg:
    if vlanCfg.name != null
    then vlanCfg.name
    else "${trunkName}.${vlanKey}";

  mkBridgeNetdev = name:
    lib.nameValuePair "20-${name}" {
      netdevConfig = {
        Kind = "bridge";
        Name = name;
      };
    };

  mkBridgeNetwork = name: bridgeCfg: {
    matchConfig.Name = name;
    address = bridgeCfg.addresses;
    networkConfig = {
      DHCP = "no";
      ConfigureWithoutCarrier = true;
      IPv6AcceptRA = false;
      IPv6SendRA = true;
      DHCPPrefixDelegation = true;
    };
    ipv6Prefixes = map (prefix: {Prefix = prefix;}) bridgeCfg.ipv6.prefixes;
    linkConfig.RequiredForOnline = "no";
  };

  bridgeNetworkEntries =
    builtins.genList
    (
      i: let
        name = builtins.elemAt bridgeNames i;
      in
        lib.nameValuePair "${toString (40 + i)}-${name}" (mkBridgeNetwork name cfg.bridges.${name})
    )
    (builtins.length bridgeNames);

  mkTrunkNetwork = trunkName: let
    trunkCfg = cfg.trunks.${trunkName};
    vlanNames = map (vlanKey: vlanDeviceName trunkName vlanKey trunkCfg.vlans.${vlanKey}) (lib.attrNames trunkCfg.vlans);
  in
    lib.nameValuePair "30-${trunkName}" ({
        matchConfig.Name = trunkName;
        linkConfig.RequiredForOnline = "no";
      }
      // lib.optionalAttrs (vlanNames != []) {
        vlan = vlanNames;
      }
      // lib.optionalAttrs (trunkCfg.untaggedBridge != null) {
        networkConfig.Bridge = trunkCfg.untaggedBridge;
      });

  vlanEntries = lib.flatten (map (trunkName: let
    trunkCfg = cfg.trunks.${trunkName};
  in
    map (vlanKey: let
      vlanCfg = trunkCfg.vlans.${vlanKey};
      name = vlanDeviceName trunkName vlanKey vlanCfg;
    in {
      netdev = lib.nameValuePair "25-${trunkName}-vlan${vlanKey}" {
        netdevConfig = {
          Kind = "vlan";
          Name = name;
        };
        vlanConfig.Id = builtins.fromJSON vlanKey;
      };
      network = lib.nameValuePair "31-${trunkName}-vlan${vlanKey}" {
        matchConfig.Name = name;
        networkConfig.Bridge = vlanCfg.bridge;
        linkConfig.RequiredForOnline = "no";
      };
    })
    (lib.attrNames trunkCfg.vlans))
  trunkNames);

  wanNetwork = lib.optionalAttrs (cfg.wan.interface != null) {
    "10-${cfg.wan.interface}" = {
      matchConfig.Name = cfg.wan.interface;
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpV4Config.UseDNS = false;
      dhcpV6Config.UseDNS = false;
      ipv6AcceptRAConfig.UseDNS = false;
      linkConfig.RequiredForOnline = "routable";
    };
  };
in {
  options.networking.homeRouter = {
    enable = lib.mkEnableOption "home router network stack";

    wan = {
      interface = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "eth0";
        description = "WAN interface used for DHCP, RA, and default NAT egress.";
      };
    };

    bridges = lib.mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          addresses = lib.mkOption {
            type = types.listOf types.str;
            default = [];
            example = ["192.168.0.1/24" "fd00::1/64"];
            description = "Addresses assigned to this LAN bridge.";
          };
          ipv6 = {
            prefixes = lib.mkOption {
              type = types.listOf types.str;
              default = [];
              example = ["fd00::/64"];
              description = "IPv6 prefixes announced on this bridge.";
            };
          };
        };
      });
      default = {};
      description = "LAN bridge definitions keyed by bridge interface name.";
    };

    trunks = lib.mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          untaggedBridge = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "br0";
            description = "Bridge receiving untagged frames from this trunk interface.";
          };
          vlans = lib.mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                name = lib.mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  example = "eth1.100";
                  description = "Optional VLAN netdev name. Defaults to <trunk>.<id>.";
                };
                bridge = lib.mkOption {
                  type = types.str;
                  example = "br0";
                  description = "Bridge receiving frames from this VLAN device.";
                };
              };
            });
            default = {};
            description = "Tagged VLANs carried by this trunk interface, keyed by VLAN ID.";
          };
        };
      });
      default = {};
      description = "Physical LAN trunk interfaces.";
    };

    nat = {
      ipv4SourceSubnet = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "192.168.0.0/24";
        description = "IPv4 source subnet masqueraded through the WAN interface.";
      };
      ipv6SourceSubnets = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["fd00::/64"];
        description = "IPv6 source subnets masqueraded through the WAN interface.";
      };
    };

    dnsmasq = {
      domain = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "lan.example.net";
        description = "Local LAN domain served by dnsmasq.";
      };
      servers = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["127.0.0.1#1054"];
        description = "Upstream DNS servers for dnsmasq.";
      };
      dhcpRanges = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["192.168.0.100,192.168.0.200,24h"];
        description = "dnsmasq dhcp-range values.";
      };
      dhcpHosts = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        description = "dnsmasq dhcp-host values.";
      };
      extraInterfaces = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["tailscale0"];
        description = "Additional interfaces on which dnsmasq should answer DNS queries.";
      };
      extraSettings = lib.mkOption {
        type = types.attrs;
        default = {};
        description = "Additional settings merged into services.dnsmasq.settings.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.wan.interface != null;
          message = "networking.homeRouter.wan.interface must be set when networking.homeRouter is enabled.";
        }
        {
          assertion = cfg.nat.ipv4SourceSubnet != null;
          message = "networking.homeRouter.nat.ipv4SourceSubnet must be set when networking.homeRouter is enabled.";
        }
        {
          assertion = cfg.dnsmasq.domain != null;
          message = "networking.homeRouter.dnsmasq.domain must be set when networking.homeRouter is enabled.";
        }
      ];

      networking.useDHCP = false;
      networking.useNetworkd = true;
      networking.firewall.enable = false;
      networking.nftables.enable = true;
      networking.nftables.flushRuleset = true;

      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = true;
        "net.ipv6.conf.all.forwarding" = true;
      };

      # Avahi owns mDNS on the LAN bridges and reflects discovery between
      # them. Keep systemd-resolved from binding a second mDNS responder.
      services.avahi = {
        enable = true;
        allowInterfaces = bridgeNames;
        ipv6 = false;
        reflector = true;
        publish = {
          enable = true;
          addresses = true;
        };
      };
      services.resolved.settings.Resolve.MulticastDNS = false;

      systemd.network = {
        enable = true;
        config.networkConfig = {
          ManageForeignRoutes = false;
          ManageForeignRoutingPolicyRules = false;
        };
        netdevs =
          lib.listToAttrs (map mkBridgeNetdev bridgeNames)
          // lib.listToAttrs (map (entry: entry.netdev) vlanEntries);
        networks =
          wanNetwork
          // lib.listToAttrs (map mkTrunkNetwork trunkNames)
          // lib.listToAttrs (map (entry: entry.network) vlanEntries)
          // lib.listToAttrs bridgeNetworkEntries;
      };
    }

    {
      networking.nftables.tables.nat = {
        family = "ip";
        content = ''
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ip saddr ${cfg.nat.ipv4SourceSubnet} oifname "${cfg.wan.interface}" masquerade
          }
        '';
      };
    }

    (lib.mkIf (cfg.nat.ipv6SourceSubnets != []) {
      networking.nftables.tables.nat6 = {
        family = "ip6";
        content = ''
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ${ipv6NatRules}
          }
        '';
      };
    })

    {
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings =
          {
            bind-dynamic = true;
            interface = bridgeNames ++ cfg.dnsmasq.extraInterfaces;
            no-resolv = true;
            server = cfg.dnsmasq.servers;
            domain = cfg.dnsmasq.domain;
            local = "/${cfg.dnsmasq.domain}/";
            expand-hosts = true;
            dhcp-range = cfg.dnsmasq.dhcpRanges;
            dhcp-host = cfg.dnsmasq.dhcpHosts;
            dhcp-authoritative = true;
          }
          // cfg.dnsmasq.extraSettings;
      };
    }

    {
      networking.nftables.tables.home-router-mss = {
        family = "inet";
        content = ''
          chain forward {
            type filter hook forward priority mangle; policy accept;
            tcp flags syn tcp option maxseg size set rt mtu
          }
        '';
      };
    }
  ]);
}
