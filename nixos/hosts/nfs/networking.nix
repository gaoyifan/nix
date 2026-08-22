{...}: {
  imports = [../../optional/edge-firewall.nix];

  networking = {
    useDHCP = false;
    useNetworkd = true;
    nameservers = [
      "202.38.64.17"
      "202.38.64.56"
    ];
    firewall.enable = false;
    edgeFirewall = {
      enable = true;
      extraInputRules = [
        ''
          ip saddr {
            172.17.172.0/24,
            192.168.93.98,
            192.168.93.151,
            192.168.93.152,
            192.168.93.160,
            202.38.93.98,
            202.38.93.152,
            202.38.93.153,
            202.38.95.82
          } accept
        ''
      ];
    };
    nftables.tables.tailscale-exit-nat = {
      family = "inet";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          iifname "tailscale0" oifname "eno2" masquerade
        }
      '';
    };
    policyRouting = {
      enable = true;
      ipv4.routingPolicyRules = {
        wanSource = [
          "from 192.168.93.155/32 lookup eno1"
          "from 202.38.93.155/32 lookup eno2"
        ];
        defaultOutlet = ["lookup main"];
      };
      ipv6.routingPolicyRules = {
        defaultOutlet = ["lookup main"];
      };
    };
  };

  systemd.network = {
    config.routeTables = {
      eno1 = 1001;
      eno2 = 1002;
    };
    links = {
      "10-eno1" = {
        matchConfig.PermanentMACAddress = "34:64:a9:9a:94:e8";
        linkConfig.Name = "eno1";
      };
      "10-eno2" = {
        matchConfig.PermanentMACAddress = "34:64:a9:9a:94:e9";
        linkConfig.Name = "eno2";
      };
    };
    networks = {
      "10-eno1" = {
        matchConfig.Name = "eno1";
        address = ["192.168.93.155/24"];
        routes = [
          {
            Gateway = "192.168.93.254";
            Table = "eno1";
          }
        ];
        networkConfig.IPv6AcceptRA = false;
        linkConfig.RequiredForOnline = "routable";
      };
      "10-eno2" = {
        matchConfig.Name = "eno2";
        address = [
          "202.38.93.155/24"
          "2001:da8:d800:931::155/64"
        ];
        routes = [
          {
            Gateway = "202.38.93.254";
          }
          {
            Gateway = "202.38.93.254";
            Table = "eno2";
          }
          {
            Gateway = "2001:da8:d800:931::1";
          }
        ];
        networkConfig.IPv6AcceptRA = false;
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };
}
