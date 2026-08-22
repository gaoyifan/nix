{...}: {
  imports = [../../optional/edge-firewall.nix];

  networking = {
    hostName = "ali-sg";
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    useDHCP = false;
    useNetworkd = true;
    edgeFirewall = {
      enable = true;
      extraPublicTcpPorts = [
        "53"
        "80"
      ];
      extraPublicUdpPorts = ["53"];
    };
  };

  systemd.network = {
    links."10-wan" = {
      matchConfig.Path = "pci-0000:00:05.0";
      linkConfig.Name = "eth0";
    };
    networks."10-wan" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  services = {
    nylon.cloudflareWarp = {
      enable = true;
      label = 101;
      ipv6Address = "2606:4700:110:8e8b:797f:40b6:888f:acfb";
      reserved = "0x1b0ed6";
    };
  };
}
