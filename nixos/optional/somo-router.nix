{
  config,
  lib,
  ...
}: let
  cfg = config.networking.somoRouter;
  homeRouter = config.networking.homeRouter;
  lanDomain = "somo.gaof.net";
  usbWanGroup = 6505;
  guestInterface = homeRouter.lans.guest.interface;
  somoInterface = homeRouter.lans.somo.interface;
  subnet = offset: toString (cfg.lanSubnetBase + offset);
  ipv4Address = offset: "100.65.${subnet offset}";
  ipv6Prefix = offset: "fd9a:2d16:5c3e:${subnet offset}";
in {
  imports = [
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
      wgIplc.enable = true;

      monitoring.enable = true;

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
      };

      routingPolicies.guest = {
        from = "guest";
        via = "cmcc";
      };

      dnsmasq = {
        domain = lanDomain;
        extraInterfaces = ["tailscale0"];
      };

      wlt = {
        enable = true;
      };

      egress.masquerade.extraRules = [
        ''ip saddr @private_v4 oifgroup ${toString usbWanGroup} masquerade''
        ''ip6 saddr @private_v6 oifgroup ${toString usbWanGroup} masquerade''
      ];
    };

    services.nylon = {
      enable = true;
      policyRouting.enable = true;
      exits.default = {
        label = 100;
        interface = homeRouter.wans.cmcc.interface;
      };
    };

    networking.edgeFirewall = {
      extraInputRules = [
        ''iifname "${guestInterface}" drop''
      ];
      extraForwardRules = [
        ''iifname "${somoInterface}" oifname "tailscale0" ip daddr 100.65.1.63 tcp dport 8178 accept''
        ''iifname "${somoInterface}" oifname "tailscale0" drop''
        ''iifname "${guestInterface}" meta nfproto ipv4 oifname "${homeRouter.wans.cmcc.interface}" accept''
        ''iifname "${guestInterface}" drop''
      ];
    };
  };
}
