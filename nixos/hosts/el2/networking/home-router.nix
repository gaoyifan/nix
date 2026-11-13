{
  config,
  lib,
  nylonTopology,
  pkgs,
  ...
}: let
  googleExit = lib.findFirst (exit: exit.nodeId == "oracle2" && exit.name == "public") null nylonTopology.topology.catalog;
in {
  imports = [
    ../../../optional/el-router.nix
    ../../../optional/home-router
  ];

  networking.homeRouter = {
    enable = true;
    wgIplc = {
      ip = "11.13.112.77/24";
      privateKeyFile = config.services.secrets.filesDir + "/nixos/el2/wg-iplc-private-key.age";
    };

    monitoring.enable = true;

    switch.ports.uplink0 = {
      bond = {
        members = [
          "eno1np0"
          "eno2np1"
        ];
        primary = "eno1np0";
      };
      tagged = [
        22
        931
      ];
    };

    lans.gnet642 = {
      vlan = 642;
      addresses = [
        "100.64.2.254/24"
        "192.168.225.1/24"
      ];
      ipv6.enable = false;
      dhcpServer = {
        range = "100.64.2.100,100.64.2.200,24h";
        settings.dhcp-range = ["192.168.225.0,static,255.255.255.0"];
      };
    };

    wans = {
      cernet = {
        vlan = 931;
        addresses = [
          "202.38.93.98/24"
          "2001:da8:d800:931::98/64"
        ];
        gateway4 = "202.38.93.254";
        gateway6 = "2001:da8:d800:931::1";
        routingTable = 93;
        defaultRoute = true;
        defaultRouteMetric = 200;
      };
      chinanet = {
        vlan = 22;
        addresses = ["202.141.162.72/25"];
        gateway4 = "202.141.162.126";
        routingTable = 162;
      };
      cmcc = {
        vlan = 22;
        addresses = ["202.141.178.7/25"];
        gateway4 = "202.141.178.126";
        routingTable = 178;
      };
    };

    avahi.enable = false;
    dnsmasq.domain = "el2.gaof.net";

    wlt = {
      dns = {
        explicitListenAddresses = [
          "100.127.100.2"
          "fd7a:115c:a1e0::5d01:b462"
          "100.64.110.254"
          "10.250.10.20"
          "fd10:250:10::20"
        ];
        entryInterfaces = [
          "tailscale0"
          "wg0"
          "nylon0"
        ];
        extraAllowedClientCidrs = [
          "100.64.110.0/24"
          "10.250.10.0/24"
          "fd10:250:10::/64"
        ];
      };
    };

    egress = {
      classification = {
        # iif 0 limits this shared classifier rule to locally generated traffic.
        extraRules = [
          ''meta iif 0 ip daddr @google counter meta mark set ${googleExit.markHex} ct mark set meta mark return''
          ''meta iif 0 ip6 daddr @google6 counter meta mark set ${googleExit.markHex} ct mark set meta mark return''
        ];
        extraIngressInterfaces = [
          "podman*"
          "wg0"
        ];
        outputClassificationInterface = "ens49f3";
      };
    };
  };

  networking.nftables.tables.home-router.content = ''
    include "${pkgs.nft-geo-sets}/set-google.conf"
    include "${pkgs.nft-geo-sets}/set-google6.conf"
  '';

  systemd.network.networks."09-management" = {
    matchConfig.Name = "ens49f3";
    address = [
      "192.168.93.98/24"
      "2001:da8:d800:931::192:98/64"
    ];
    routes = [
      {
        Gateway = "192.168.93.254";
        GatewayOnLink = true;
        PreferredSource = "192.168.93.98";
        Metric = 100;
      }
      {
        Gateway = "2001:da8:d800:931::1";
        GatewayOnLink = true;
        PreferredSource = "2001:da8:d800:931::192:98";
        Metric = 100;
      }
    ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  networking.elRouter.enable = true;
}
