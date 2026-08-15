{...}: {
  networking = {
    hostName = "google";
    nameservers = ["169.254.169.254"];
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
  };

  systemd.network = {
    links."10-wan" = {
      matchConfig.Path = "pci-0000:00:04.0";
      linkConfig = {
        Name = "ens4";
        MTUBytes = 1460;
      };
    };
    networks."10-wan" = {
      matchConfig.Name = "ens4";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
