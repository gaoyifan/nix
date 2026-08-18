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

  services.tailscale.port = 6627;
}
