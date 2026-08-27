{config, ...}: let
  dhcpHosts = import (config.services.secrets.filesDir + "/nixos/cjia/dhcp-hosts.nix");
  pppMark = "0x001";
  nylonEl2CernetMark = "0x200";
in {
  imports = [
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
    };

    dnsmasq = {
      domain = "cjia.gaof.net";
      extraInterfaces = ["tailscale0"];
    };

    monitoring.enable = true;

    wlt.enable = true;

    egress.classification = {
      extraIngressInterfaces = ["tailscale0"];
      extraRules = [
        ''meta nfproto ipv4 udp dport { 3478-3497, 16384-16387, 16393-16402 } meta mark set ${pppMark} ct mark set meta mark return''
      ];
      destinationAddressSetRules = [
        {
          set = "ustc";
          mark = nylonEl2CernetMark;
        }
        {
          set = "cn";
          mark = pppMark;
        }
      ];
    };
  };
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
}
