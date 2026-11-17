{
  config,
  lib,
  ...
}: {
  imports = [../../optional/home-router];

  age.secrets.wifi = lib.mkIf config.services.secrets.hasRealFiles {
    file = config.services.secrets.filesDir + "/nixos/somo-hp-pc/wifi.age";
    owner = "wpa_supplicant";
  };

  networking = {
    hostName = "somo-hp-pc";
    useDHCP = false;
    useNetworkd = true;
    homeRouter = {
      enable = true;

      wgIplc = {
        enable = true;
        ip = "11.13.112.82/24";
        privateKeyFile = config.services.secrets.filesDir + "/nixos/somo-hp-pc/wg-iplc-private-key.age";
      };

      # Switch port 23 carries the upstream untagged and the Wi-Fi LAN tagged.
      switch.ports.enp1s0 = {
        untagged = 20;
        tagged = [654];
      };

      wans.uplink = {
        vlan = 20;
        addresses = ["192.168.20.253/24"];
        gateway4 = "192.168.20.254";
        defaultRoute = true;
        defaultRouteMetric = 100;
      };

      lans.internet = {
        vlan = 654;
        addresses = ["100.65.4.254/24"];
        dhcpServer.range = "100.65.4.100,100.65.4.200,24h";
        ipv6.enable = false;
      };

      avahi.enable = false;
      dnsmasq.domain = "somo3.gaof.net";
    };

    wireless = {
      enable = true;
      secretsFile = "/run/agenix/wifi";
      networks.ZMXC.pskRaw = "ext:psk";
    };
  };

  systemd.network = {
    wait-online.anyInterface = true;
    networks = {
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
