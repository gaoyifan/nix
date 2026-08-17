{
  config,
  lib,
  ...
}: let
  homeRouter = config.networking.homeRouter;
  cernetInterface = homeRouter.wans.cernet.interface;
  chinanetInterface = homeRouter.wans.chinanet.interface;
  managementInterface = "ens161";
  managementAddress = "192.168.93.152";
  managementTable = 9300;
in {
  imports = [
    ../../optional/gnet-edge-router.nix
    ../../optional/home-router
  ];

  networking.homeRouter = {
    enable = true;
    wgIplc = {
      ip = "11.13.112.74/24";
      privateKeyFile = config.services.secrets.filesDir + "/nixos/el/wg-iplc-private-key.age";
    };

    monitoring = {
      enable = true;
      wans = [
        "cernet"
        "chinanet"
        "cmcc"
      ];
    };

    # VMXNET3 adapters 1-3 are untagged access ports. Adapter 4 is the
    # standalone management network and must not join the core bridge.
    switch.ports = {
      ens192.untagged = 641;
      ens224.untagged = 931;
      ens256.untagged = 22;
    };

    lans.gnet641 = {
      vlan = 641;
      addresses = ["100.64.1.254/24"];
      ipv6.enable = false;
      dhcpServer.range = "100.64.1.100,100.64.1.200,1h";
    };

    wans = {
      cernet = {
        vlan = 931;
        addresses = [
          "202.38.93.152/24"
          "2001:da8:d800:931::152/64"
        ];
        gateway4 = "202.38.93.254";
        gateway6 = "2001:da8:d800:931::1";
        routingTable = 93;
        defaultRoute = true;
        routes = [
          {
            Destination = "192.168.174.0/24";
            Gateway = "202.38.93.254";
          }
          {
            Destination = "202.38.64.0/24";
            Gateway = "202.38.93.254";
          }
        ];
      };
      chinanet = {
        vlan = 22;
        addresses = ["202.141.162.122/24"];
        gateway4 = "202.141.162.126";
        routingTable = 162;
      };
      cmcc = {
        vlan = 22;
        addresses = ["202.141.178.12/24"];
        gateway4 = "202.141.178.126";
        routingTable = 178;
      };
    };

    avahi.enable = false;
    dnsmasq = {
      domain = "el.gaof.net";
      extraInterfaces = [
        "tailscale0"
        "wg-iplc"
      ];
    };

    wlt = {
      enable = true;
      domain = "gaof.net";
      defaultOutlet.ipv6 = "disabled";
    };
  };

  systemd.network = {
    config.routeTables.management = managementTable;
    networks."09-management" = {
      matchConfig.Name = managementInterface;
      address = ["${managementAddress}/24"];
      routes = [
        {
          Gateway = "192.168.93.254";
          GatewayOnLink = true;
          PreferredSource = managementAddress;
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
    "from ${managementAddress}/32 lookup management"
  ];

  networking.gnetEdgeRouter = {
    enable = true;
    lan = "gnet641";
    unclassifiedIpv4Sources = [managementAddress];
    masqueradeInterfaces = [managementInterface];
  };

  networking.edgeFirewall = {
    publicTcpPorts = [
      "22"
      "5201"
      "29979-29980"
    ];
    publicUdpPorts = [
      "5201"
      "6622"
      "6627"
      "61001-61999"
    ];
    extraForwardRules = ["ct status dnat accept"];
  };

  networking.nftables.tables.el-dnat = {
    family = "inet";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname { "${cernetInterface}", "${chinanetInterface}" } fib daddr type local udp dport 2197 dnat ip to 202.38.93.98
      }
    '';
  };
}
