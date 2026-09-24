{
  config,
  lib,
  ...
}: {
  imports = [
    ../../optional/home-router
    ../../optional/oob-ssh.nix
  ];

  networking.homeRouter.wgIplc = {
    enable = true;
    ip = "11.13.112.81/24";
    privateKeyFile = config.services.secrets.filesDir + "/nixos/baihualin/wg-iplc-private-key.age";
  };

  services.oobSsh = {
    enable = true;
    parentInterface = "wan0";
    address = "198.18.233.235/24";
  };

  # DAD cannot finish without LAN carrier, but this ULA is also routed over Tailscale.
  systemd.network.networks."41-baihualin" = {
    address = lib.mkForce ["100.66.1.254/24"];
    addresses = [
      {
        Address = "fd9a:2d16:5c3e:6601::254/64";
        DuplicateAddressDetection = "none";
      }
    ];
  };

  networking.homeRouter = {
    enable = true;
    monitoring.enable = true;

    switch.ports.lan1.untagged = 661;
    lans.baihualin = {
      vlan = 661;
      addresses = [
        "100.66.1.254/24"
        "fd9a:2d16:5c3e:6601::254/64"
      ];
      dhcpServer.range = "100.66.1.100,100.66.1.200,24h";
      ipv6.prefixes = ["fd9a:2d16:5c3e:6601::/64"];
    };

    wans.chinanet = {
      device = "wan0";
      dhcp = true;
    };

    dnsmasq.domain = "baihualin.gaof.net";
    wlt.dns = {
      entryInterfaces = [
        "tailscale0"
        "nylon0"
      ];
      extraAllowedClientCidrs = [
        "10.250.10.0/24"
        "fd10:250:10::/64"
      ];
      explicitListenAddresses = [
        "100.127.101.99"
        "fd7a:115c:a1e0::f42a:494a"
        "10.250.10.35"
        "fd10:250:10::35"
      ];
    };
  };
}
