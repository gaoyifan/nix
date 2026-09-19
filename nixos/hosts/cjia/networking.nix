{
  config,
  lib,
  ...
}: let
  dhcpHosts = import (config.services.secrets.filesDir + "/nixos/cjia/dhcp-hosts.nix");
  pppMark = "0x001";
  nylonEl2CernetMark = "0x200";
  pppoeOnlyClientMac = "20:26:06:09:a7:08";
in {
  imports = [
    ../../optional/home-router
    ../../optional/oob-ssh.nix
  ];

  services.oobSsh = {
    enable = true;
    parentInterface = "wan0";
    address = "198.18.233.233/24";
  };

  networking.homeRouter = {
    enable = true;
    ttr.enable = true;
    wgIplc = {
      enable = true;
      ip = "11.13.112.43/24";
      privateKeyFile = config.services.secrets.filesDir + "/nixos/cjia/wg-iplc-private-key.age";
    };

    switch.ports.lan1.untagged = 651;

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

    dnsmasq.domain = "cjia.gaof.net";

    monitoring.enable = true;

    wlt = {
      dns = {
        explicitListenAddresses = [
          "100.127.100.3"
          "fd7a:115c:a1e0::b01:6d26"
          "10.250.10.17"
          "fd10:250:10::17"
        ];
        entryInterfaces = [
          "tailscale0"
          "nylon0"
        ];
        extraAllowedClientCidrs = [
          "10.250.10.0/24"
          "fd10:250:10::/64"
        ];
      };
    };

    egress.classification = {
      extraIngressInterfaces = ["tailscale0"];
      extraRules = [
        ''ether saddr ${pppoeOnlyClientMac} ip daddr != @private_v4 meta mark set ${pppMark} ct mark set meta mark return''
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

    # The optical modem has no return route for the LAN subnet.
    egress.masquerade.extraInterfaces = ["br-core.650"];
  };

  # Proxying would bypass this client's MAC-based forward restriction below.
  # The native ruleset runs after table definitions, within the same transaction.
  networking.nftables.ruleset = lib.mkIf (config.networking.homeRouter.enable && config.networking.homeRouter.ttr.enable) ''
    insert rule inet home-router tcp-repeater-prerouting ether saddr ${pppoeOnlyClientMac} return
  '';

  # Routed traffic initiated by this client may only leave through PPPoE.
  networking.nftables.tables.pppoe-only-client = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter - 10; policy accept;
        ct direction original ether saddr ${pppoeOnlyClientMac} oifname != "ppp0" counter drop
      }
    '';
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
