{...}: {
  networking = {
    hostName = "misc1-sz";
    useDHCP = false;
    useNetworkd = true;

    policyRouting = {
      enable = true;
      ipv4.routingPolicyRules.wanSource = [
        "from 14.215.130.15/32 lookup shenzhen"
        "fwmark 0x100 lookup shenzhen"
      ];
    };
  };

  systemd.network = {
    config.routeTables.shenzhen = 100;

    links = {
      "10-eth0" = {
        matchConfig.PermanentMACAddress = "8e:2f:57:b9:92:1e";
        linkConfig.Name = "eth0";
      };
      "10-eth1" = {
        matchConfig.PermanentMACAddress = "36:73:2d:cf:a4:87";
        linkConfig.Name = "eth1";
      };
    };

    networks = {
      "10-eth0" = {
        matchConfig.Name = "eth0";
        address = ["58.84.55.69/28"];
        routes = [
          {
            Gateway = "58.84.55.65";
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
        address = ["14.215.130.15/25"];
        routes = [
          {
            Gateway = "14.215.130.1";
            Table = "shenzhen";
          }
        ];
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };
}
