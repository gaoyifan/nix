{...}: {
  networking = {
    hostName = "do";
    nameservers = [
      "67.207.67.2"
      "67.207.67.3"
    ];
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    nftables.tables.do-nat = {
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          ip saddr 58.84.55.67 udp dport 2408 dnat ip to 162.159.192.1:2408
        }

        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "eth0" ct status dnat masquerade
        }
      '';
    };
  };

  systemd.network = {
    links = {
      "10-wan" = {
        matchConfig.Path = "pci-0000:00:03.0";
        linkConfig.Name = "eth0";
      };
      "11-vpc" = {
        matchConfig.Path = "pci-0000:00:04.0";
        linkConfig.Name = "eth1";
      };
    };
    networks = {
      "10-wan" = {
        matchConfig.Name = "eth0";
        address = [
          "128.199.153.92/18"
          "10.15.0.5/16"
          "2400:6180:0:d2:0:2:585d:d000/128"
        ];
        routes = [
          {Gateway = "128.199.128.1";}
          {Gateway = "::";}
        ];
        networkConfig.IPv6AcceptRA = false;
        linkConfig.RequiredForOnline = "routable";
      };
      "11-vpc" = {
        matchConfig.Name = "eth1";
        address = ["10.130.24.217/16"];
        linkConfig.RequiredForOnline = "no";
      };
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
