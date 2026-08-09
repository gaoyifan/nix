{
  config,
  lib,
  ...
}: let
  managementTable = 9300;
  wgIplcMark = "0x100";
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    wlt-server-key.file = config.services.secrets.filesDir + "/nixos/wlt-server-key.pem.age";
    wlt-ssh-host-key.file = config.services.secrets.filesDir + "/nixos/wlt-ssh-host-key.age";
  };

  imports = [
    ../../optional/gnet-edge-router.nix
    ../../optional/home-router
  ];

  networking.homeRouter = {
    enable = true;

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
      dhcpServer.range = "100.64.2.100,100.64.2.200,24h";
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
      servers = [
        "/cjia.gaof.net/100.65.1.254"
        "127.0.0.1#1054"
      ];
      extraInterfaces = [
        "lo"
        "tailscale0"
        "wg0"
      ];
    };

    wlt = {
      enable = true;
      domain = "gaof.net";
      defaultOutlet = {
        ipv4Mark = wgIplcMark;
        ipv6 = "disabled";
      };
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

  networking.policyRouting.ipv4.rules = lib.mkBefore [
    "pref 150 from 192.168.93.98/32 lookup management"
  ];

  networking.gnetEdgeRouter = {
    enable = true;
    lan = "gnet642";
    wgIplc.mark = wgIplcMark;
    unclassifiedIpv4Sources = ["192.168.93.98"];
    masqueradeInterfaces = ["ens49f3"];
  };

  networking.edgeFirewall = {
    trustedInterfaces = ["wg0"];
    publicTcpPorts = [
      "22"
      "5201"
      "8501"
      "10000-10003"
      "29979-29980"
    ];
    publicUdpPorts = [
      "2197"
      "3478"
      "5201"
      "6622"
      "6627"
      "61001-61999"
    ];
    extraInputRules = [
      ''iifname "podman*" meta l4proto { tcp, udp } th dport 53 accept''
      ''iifname "podman*" tcp dport 8000 accept''
    ];
    extraForwardRules = [''iifname "podman*" accept''];
  };
}
