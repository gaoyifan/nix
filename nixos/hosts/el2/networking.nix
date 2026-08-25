{
  config,
  lib,
  ...
}: let
  managementTable = 9300;
in {
  imports = [
    ../../optional/el-router.nix
    ../../optional/home-router
  ];

  networking.homeRouter = {
    enable = true;
    wgIplc = {
      ip = "11.13.112.77/24";
      privateKeyFile = config.services.secrets.filesDir + "/nixos/el2/wg-iplc-private-key.age";
    };

    monitoring = {
      enable = true;
      wans = [
        "cernet"
        "chinanet"
        "cmcc"
      ];
    };

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
    dnsmasq = {
      domain = "el2.gaof.net";
      extraInterfaces = [
        "tailscale0"
        "wg0"
      ];
    };

    wlt = {
      enable = true;
    };
  };

  systemd.network = {
    config.routeTables.management = managementTable;
    networks."09-management" = {
      matchConfig.Name = "ens49f3";
      address = ["192.168.93.98/24"];
      routes = [
        {
          Gateway = "192.168.93.254";
          GatewayOnLink = true;
          PreferredSource = "192.168.93.98";
          Table = "management";
        }
      ];
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  networking.policyRouting.ipv4.routingPolicyRules.preMain = lib.mkBefore [
    "from 192.168.93.98/32 lookup management"
  ];

  networking.elRouter = {
    enable = true;
    unclassifiedIpv4Sources = ["192.168.93.98"];
    masqueradeInterfaces = ["ens49f3"];
  };

  networking.edgeFirewall = {
    extraTrustedInterfaces = ["wg0"];
    extraPublicTcpPorts = [
      "8501"
      "10000"
      "29979-29980"
    ];
    extraPublicUdpPorts = [
      "2197"
      "3478"
    ];
    extraInputRules = [
      ''iifname "podman*" meta l4proto { tcp, udp } th dport 53 accept''
      ''iifname "podman*" tcp dport 8000 accept''
    ];
    extraForwardRules = [''iifname "podman*" accept''];
  };
}
