{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.somoRouter;
  homeRouter = config.networking.homeRouter;
  lanDomain = "somo.gaof.net";
  usbWanGroup = 6505;
  wgIplc = import (config.services.secrets.filesDir + "/nixos/${config.networking.hostName}/wg-iplc.nix");
  guestInterface = homeRouter.lans.guest.interface;
  somoInterface = homeRouter.lans.somo.interface;
  subnet = offset: toString (cfg.lanSubnetBase + offset);
  ipv4Address = offset: "100.65.${subnet offset}";
  ipv6Prefix = offset: "fd9a:2d16:5c3e:${subnet offset}";
in {
  imports = [
    ./diverge.nix
    ./home-router
    ./nylon.nix
  ];

  options.networking.somoRouter = {
    enable = lib.mkEnableOption "shared SOMO router configuration";
    wanDevice = lib.mkOption {
      type = lib.types.str;
      description = "Physical CMCC WAN interface.";
    };
    lanPort = lib.mkOption {
      type = lib.types.str;
      description = "Physical LAN switch port.";
    };
    nativeVlan = lib.mkOption {
      type = lib.types.ints.between 1 4094;
      description = "VLAN carried untagged by the physical LAN port.";
    };
    lanSubnetBase = lib.mkOption {
      type = lib.types.ints.between 0 253;
      description = "Last octet/hextet used by the gnet subnet; somo and guest use the next two values.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.usbmuxd.enable = true;
    services.diverge.enable = true;

    systemd.network.networks."11-usb-wan" = {
      matchConfig.Driver = "ipheth rndis_host";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
      dhcpV4Config = {
        RouteMetric = 512;
        UseDNS = false;
      };
      linkConfig.Group = usbWanGroup;
    };

    networking.homeRouter = {
      enable = true;

      monitoring = {
        enable = true;
        wan = "cmcc";
        grafana = {
          port = 3001;
          extraInterfaces = ["tailscale0"];
        };
      };

      switch.ports.${cfg.lanPort} = {
        untagged = cfg.nativeVlan;
        tagged = lib.remove cfg.nativeVlan [
          652
          653
          654
        ];
      };

      lans = {
        gnet = {
          vlan = 652;
          addresses = [
            "${ipv4Address 0}.254/24"
            "${ipv6Prefix 0}::254/64"
          ];
          dns = ["${ipv4Address 0}.254"];
          domains = ["~${lanDomain}"];
          dhcpServer.range = "${ipv4Address 0}.100,${ipv4Address 0}.200,24h";
          ipv6.prefixes = ["${ipv6Prefix 0}::/64"];
        };

        somo = {
          vlan = 653;
          addresses = [
            "${ipv4Address 1}.254/24"
            "${ipv6Prefix 1}::254/64"
          ];
          dhcpServer.range = "${ipv4Address 1}.100,${ipv4Address 1}.200,24h";
          ipv6.prefixes = ["${ipv6Prefix 1}::/64"];
        };

        guest = {
          vlan = 654;
          addresses = ["${ipv4Address 2}.254/24"];
          guest = true;
          dhcpServer = {
            range = "set:guest,${ipv4Address 2}.100,${ipv4Address 2}.200,24h";
            settings.dhcp-option = [
              "tag:guest,option:dns-server,223.5.5.5,223.6.6.6"
            ];
          };
          ipv6.enable = false;
        };
      };

      wans.cmcc = {
        device = cfg.wanDevice;
        dhcp = true;
        masquerade = {
          ipv4SourceSubnets = ["100.64.0.0/10"];
          ipv6SourceSubnets = [
            "${ipv6Prefix 0}::/64"
            "${ipv6Prefix 1}::/64"
          ];
        };
      };

      routingPolicies.guest = {
        from = "guest";
        via = "cmcc";
      };

      dnsmasq = {
        domain = lanDomain;
        servers = [
          "/cjia.gaof.net/100.65.1.254"
          "127.0.0.1#1054"
        ];
        extraInterfaces = ["tailscale0"];
      };

      wlt = {
        enable = true;
        domain = "gaof.net";
        defaultOutlet = {
          ipv4Mark = wgIplc.mark;
          ipv6 = "disabled";
        };
      };
    };

    services.nylon = {
      enable = true;
      policyRouting.enable = true;
      overlay = {
        ipv4Subnet = "10.250.10.0/24";
        ipv6Subnet = "fd10:250:10::/64";
      };
      exits.default = {
        label = 100;
        interface = homeRouter.wans.cmcc.interface;
      };
    };

    networking.policyRouting = {
      enable = true;
      ipv4.rules = [
        "pref 100 lookup main suppress_prefixlength 0"
        "pref 200 fwmark ${wgIplc.mark}/0xffffffff lookup ${wgIplc.routeTable}"
        "pref 32766 lookup main"
        "pref 32767 lookup default"
      ];
      ipv6.rules = [
        "pref 100 lookup main suppress_prefixlength 0"
        "pref 32766 lookup main"
      ];
    };

    services.resolved.settings.Resolve = {
      DNS = [
        "1.1.1.1"
        "1.0.0.1"
      ];
      Domains = ["~."];
    };
    services.resolved.dnsDelegates = {
      cjia.Delegate = {
        DNS = ["100.65.1.254"];
        Domains = ["cjia.gaof.net"];
      };
      wgIplcEndpoint.Delegate = {
        DNS = [
          "223.5.5.5"
          "223.6.6.6"
        ];
        Domains = ["int.automesh.org"];
      };
    };

    networking.nftables.tables.filter = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter; policy accept;
          iifname "${guestInterface}" udp dport 67 accept
          iifname "${guestInterface}" drop
        }

        chain forward {
          type filter hook forward priority filter; policy accept;
          iifname "${somoInterface}" oifname "tailscale0" ct state established,related accept
          iifname "${somoInterface}" oifname "tailscale0" ip daddr 100.65.1.63 tcp dport 8178 accept
          iifname "${somoInterface}" oifname "tailscale0" drop
          iifname "${guestInterface}" meta nfproto ipv4 oifname "${homeRouter.wans.cmcc.interface}" accept
          iifname "${guestInterface}" drop
        }
      '';
    };

    networking.nftables.tables.somo-host-egress = {
      family = "inet";
      content = ''
        include "${pkgs.nft-geo-sets}/set-cn.conf"
        include "${pkgs.nft-geo-sets}/set-cn6.conf"

        chain output {
          type route hook output priority mangle; policy accept;
          meta mark != 0 return
          udp sport ${toString config.services.nylon.udpPort} return
          ip daddr != @cn meta mark set ${wgIplc.mark}
          ip6 daddr != @cn6 icmpv6 type echo-request return
          ip6 daddr != @cn6 meta l4proto tcp reject with tcp reset
          ip6 daddr != @cn6 reject with icmpv6 type no-route
        }
      '';
    };

    networking.nftables.tables.wg-iplc-nat = {
      family = "ip";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "${wgIplc.interfaceName}" meta mark ${wgIplc.mark} masquerade
        }
      '';
    };

    networking.nftables.tables.usb-wan-nat = {
      family = "ip";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr 100.64.0.0/10 oifgroup ${toString usbWanGroup} masquerade
        }
      '';
    };
  };
}
