{...}: {
  networking = {
    hostName = "ali-sg";
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    nftables = {
      enable = true;
      tables = {
        public-input = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority filter; policy accept;
              iifname != "eth0" return

              ct state established,related accept
              iifname "lo" accept
              ip protocol icmp accept
              meta l4proto ipv6-icmp accept

              udp sport 67 udp dport 68 accept
              udp sport 547 udp dport 546 accept

              tcp dport { 22, 53, 80 } accept
              udp dport { 53, 6622, 6627 } accept

              counter drop
            }
          '';
        };
      };
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
    tailscale.port = 6627;
  };
}
