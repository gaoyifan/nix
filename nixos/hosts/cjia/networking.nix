{
  config,
  lib,
  pkgs,
  ...
}: let
  homeRouter = config.networking.homeRouter;
  lanInterface = homeRouter.lans.cjia.interface;
  dhcpHosts = import (config.services.secrets.filesDir + "/nixos/cjia/dhcp-hosts.nix");
  pppMark = "0x1";
  nylonEl2CernetMark = "0x200";
in {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/home-router
    ../../optional/oob-ssh.nix
  ];

  services.oobSsh = {
    enable = true;
    parentInterface = "end0";
    address = "198.18.233.233/24";
  };

  networking.homeRouter = {
    enable = true;
    wgIplc = {
      enable = true;
      ip = "11.13.112.43/24";
      privateKeyFile = config.services.secrets.filesDir + "/nixos/cjia/wg-iplc-private-key.age";
    };

    switch.ports.enp1s0.untagged = 651;

    lans.cjia = {
      vlan = 651;
      addresses = ["100.65.1.254/24"];
      ipv6.enable = false;
      dhcpServer = {
        range = "100.65.1.100,100.65.1.199,24h";
        hosts = dhcpHosts;
      };
    };

    wans.ppp = {
      device = "ppp0";
      routes = [
        {
          Destination = "0.0.0.0/0";
          Table = "ppp";
        }
      ];
      masquerade.ipv4SourceSubnets = ["100.64.0.0/10"];
    };

    dnsmasq = {
      domain = "cjia.gaof.net";
      extraInterfaces = ["tailscale0"];
    };

    monitoring = {
      enable = true;
      wans = ["ppp"];
    };

    wlt = {
      enable = true;
    };
  };

  networking.edgeFirewall.enable = true;

  systemd.network = {
    config.routeTables.ppp = 1000;
    networks."10-wan-ppp" = {
      linkConfig.RequiredForOnline = "routable";
      networkConfig = {
        KeepConfiguration = true;
        LinkLocalAddressing = false;
      };
    };
  };

  networking.policyRouting.ipv4.routingPolicyRules = {
    wltOutlet = [
      "fwmark ${pppMark}/0xfff lookup ppp"
    ];
    defaultOutlet = ["lookup ppp"];
  };

  networking.nftables.tables = {
    cjia = {
      family = "inet";
      content = ''
        include "${pkgs.nft-geo-sets}/set-cn.conf"

        set ustc {
          type ipv4_addr
          flags constant, interval
          elements = {
            10.10.151.0/24, 10.38.0.0/16, 10.70.0.0/16,
            10.254.0.0/16, 114.214.160.0/19, 114.214.192.0/18,
            118.31.51.206, 121.255.0.0/16, 172.16.0.0/16,
            192.168.93.0/24, 192.168.174.0/24, 192.168.193.0/24,
            202.38.64.0/19, 202.141.176.0/20, 210.45.64.0/20,
            210.45.112.0/20, 210.72.22.0/24, 211.86.144.0/20,
            218.22.21.0/27, 222.195.64.0/19
          }
        }

        chain classify {
          meta mark != 0 ct mark set meta mark return
          udp dport { 3478-3497, 16384-16387, 16393-16402 } meta mark set ${pppMark}
          meta mark 0 tcp dport 5223 meta mark set ${pppMark}
          meta mark 0 ip daddr @ustc meta mark set ${nylonEl2CernetMark}
          meta mark 0 ip daddr @cn meta mark set ${pppMark}
          meta mark 0 meta nfproto ipv4 meta mark set ${homeRouter.wgIplc.mark}
          ct mark set meta mark
        }

        chain prerouting {
          type filter hook prerouting priority mangle; policy accept;
          ct mark != 0 meta mark set ct mark
          iifname { "${lanInterface}", "tailscale0" } jump classify
        }

        chain output {
          type route hook output priority mangle; policy accept;
          meta mark != 0 return
          meta mark set ct mark
          meta mark != 0 return
          udp sport { ${toString config.services.nylon.udpPort}, ${toString config.services.tailscale.port} } return
          ip daddr @ustc meta mark set ${nylonEl2CernetMark} return
          ip daddr @cn meta mark set ${pppMark} return
          meta nfproto ipv4 meta mark set ${homeRouter.wgIplc.mark}
        }

        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          meta mark ${homeRouter.wgIplc.mark} oifname "wg-iplc" masquerade
        }
      '';
    };
  };
}
