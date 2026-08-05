{
  config,
  pkgs,
  ...
}: let
  homeRouter = config.networking.homeRouter;
  internalInterface = homeRouter.lans.gnet642.interface;
  cernetInterface = homeRouter.wans.cernet.interface;
  vlan22Interface = homeRouter.wans.chinanet.interface;
  managementTable = 9300;
  wgIplcMark = "0x100";
  wgIplcTable = "5110";
in {
  imports = [
    ../../optional/home-router
    ../../optional/nylon.nix
  ];

  networking.homeRouter = {
    enable = true;

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
      domain = "lab.gaof.net";
      servers = [
        "/cjia.gaof.net/100.65.1.254"
        "127.0.0.1#1054"
      ];
      extraInterfaces = [
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
    networks = {
      "09-management" = {
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
  };

  networking.policyRouting = {
    enable = true;
    ipv4 = {
      rules = [
        "pref 150 from 192.168.93.98/32 lookup management"
        "pref 200 fwmark ${wgIplcMark}/0xffffffff lookup ${wgIplcTable}"
        "pref 400 from 100.64.0.0/10 lookup cernet"
        "pref 400 from 192.168.225.0/24 lookup cernet"
        "pref 32766 lookup main"
        "pref 32767 lookup default"
      ];
    };
    ipv6 = {
      rules = [
        "pref 32766 lookup main"
      ];
    };
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
        gateway4 = "202.38.93.254";
        ipv4Address = "202.38.93.98";
        ipv6Address = "2001:da8:d800:931::98";
      };
      chinanet = {
        label = 101;
        interface = vlan22Interface;
        gateway4 = "202.141.162.126";
        ipv4Address = "202.141.162.72";
      };
      cmcc = {
        label = 102;
        interface = vlan22Interface;
        gateway4 = "202.141.178.126";
        ipv4Address = "202.141.178.7";
      };
    };
  };

  # Classify unmarked traffic after WLT and inbound conntrack restoration.
  # The non-default public source identities retain their selected WAN.
  networking.nftables.tables.el2-egress = {
    family = "inet";
    content = ''
      include "${pkgs.nft-geo-sets}/set-cn.conf"
      include "${pkgs.nft-geo-sets}/set-cn6.conf"
      include "${pkgs.nft-geo-sets}/set-cernet.conf"
      include "${pkgs.nft-geo-sets}/set-chinanet.conf"
      include "${pkgs.nft-geo-sets}/set-cmcc.conf"

      chain classify {
        meta mark != 0 return
        ip saddr 192.168.93.98 return
        udp sport { 2197, 6622, 6627 } return

        ip saddr 202.141.162.72 meta mark set 162 return
        ip saddr 202.141.178.7 meta mark set 178 return

        ip daddr @cernet meta mark set 93 return
        ip daddr @chinanet meta mark set 162 return
        ip daddr @cmcc meta mark set 178 return
        ip daddr @cn meta mark set 162 return
        meta nfproto ipv4 meta mark set ${wgIplcMark} return

        ip6 daddr @cn6 meta mark set 93 return
        ip6 daddr != @cn6 icmpv6 type echo-request return
        ip6 daddr != @cn6 meta mark set 0xff
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

  networking.nftables.tables.el2-nat = {
    family = "inet";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "ens49f3" masquerade
        meta mark ${wgIplcMark} oifname "wg-iplc" masquerade
        meta mark 93 oifname "${cernetInterface}" snat ip to 202.38.93.98
        meta mark 162 oifname "${vlan22Interface}" snat ip to 202.141.162.72
        meta mark 178 oifname "${vlan22Interface}" snat ip to 202.141.178.7
      }
    '';
  };

  networking.nftables.tables.el2-filter = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        iifname "lo" accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        tcp dport 22 accept
        tcp dport { 5201, 10000-10003, 29979-29980 } accept
        udp dport { 2197, 3478, 5201, 6622, 6627 } accept
        udp dport 61001-61999 accept

        iifname "${internalInterface}" udp dport { 53, 67 } accept
        iifname "${internalInterface}" tcp dport { 53, 80, 443, 2222 } accept
        iifname { "tailscale0", "wg0" } udp dport 53 accept
        iifname { "tailscale0", "wg0" } tcp dport { 53, 80, 443, 2222 } accept
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        ct status dnat accept
        iifname { "${internalInterface}", "tailscale0", "wg0", "nylon0" } accept
        iifname "podman*" accept
      }
    '';
  };
}
