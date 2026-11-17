{
  config,
  lib,
  ...
}: {
  age.secrets.wifi = lib.mkIf config.services.secrets.hasRealFiles {
    file = config.services.secrets.filesDir + "/nixos/somo-hp-pc/wifi.age";
    owner = "wpa_supplicant";
  };

  networking = {
    hostName = "somo-hp-pc";
    useDHCP = false;
    useNetworkd = true;
    nameservers = ["223.5.5.5" "119.29.29.29"];
    wireless = {
      enable = true;
      secretsFile = "/run/agenix/wifi";
      networks.ZMXC.pskRaw = "ext:psk";
    };
  };

  systemd.network = {
    wait-online.anyInterface = true;
    networks = {
      "10-lan" = {
        matchConfig.Type = "ether";
        address = ["192.168.20.253/24"];
        routes = [{Gateway = "192.168.20.254";}];
        networkConfig.IPv6AcceptRA = false;
      };
      "20-wlan" = {
        matchConfig.Type = "wlan";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = false;
        };
        # The DHCP route's default metric (1024) keeps wired preferred.
        dhcpV4Config.UseDNS = false;
      };
    };
  };

  services.resolved.settings.Resolve.FallbackDNS = [];
}
