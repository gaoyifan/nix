{...}: {
  networking = {
    hostName = "misc1-sh";
    # The internal el2.gaof.net DNS delegate is itself reached over Tailscale,
    # while el2 also hosts the custom DERP relay.  This IPv4-only host needs
    # the relay's public addresses to break that bootstrap dependency.
    hosts = {
      "202.38.93.98" = ["el2.gaof.net"];
      "202.141.162.72" = ["el2.gaof.net"];
      "202.141.178.7" = ["el2.gaof.net"];
    };
    useDHCP = false;
    useNetworkd = true;

    policyRouting = {
      enable = true;
      ipv4.routingPolicyRules.wanSource = [
        "from 61.172.164.79/32 lookup shanghai"
        "fwmark 0x100 lookup shanghai"
      ];
    };
  };

  systemd.network = {
    config.routeTables.shanghai = 100;

    links = {
      "10-eth0" = {
        matchConfig.PermanentMACAddress = "2a:ae:f4:64:6d:0e";
        linkConfig.Name = "eth0";
      };
      "10-eth1" = {
        matchConfig.PermanentMACAddress = "e2:1e:1a:33:76:68";
        linkConfig.Name = "eth1";
      };
    };

    networks = {
      "10-eth0" = {
        matchConfig.Name = "eth0";
        address = ["103.90.137.101/27"];
        routes = [
          {
            Gateway = "103.90.137.97";
          }
        ];
        networkConfig = {
          DNS = [
            "1.1.1.1"
            "1.0.0.1"
          ];
        };
        linkConfig.RequiredForOnline = "routable";
      };

      "10-eth1" = {
        matchConfig.Name = "eth1";
        address = ["61.172.164.79/24"];
        routes = [
          {
            Gateway = "61.172.164.1";
            Table = "shanghai";
          }
          {
            Destination = "202.141.160.0/20";
            Gateway = "61.172.164.1";
          }
        ];
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };
}
