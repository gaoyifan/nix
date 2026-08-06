{...}: {
  imports = [
    ../qemu-guest.nix
    ../tailscale-gnet.nix
    ../nylon.nix
    ./disk-config.nix
  ];

  networking = {
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    nftables = {
      enable = true;
      tables.tailscale-exit-node-nat = {
        family = "ip";
        content = ''
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ip saddr 100.64.0.0/10 meta oiftype ether masquerade
          }
        '';
      };
    };
  };

  systemd.network.networks."10-wan" = {
    matchConfig.Type = "ether";
    networkConfig = {
      DNS = [
        "1.1.1.1"
        "1.0.0.1"
      ];
      IPv6AcceptRA = false;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  boot = {
    loader.grub.enable = true;
    kernelParams = ["console=tty0"];
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };

  services = {
    timesyncd = {
      enable = true;
      extraConfig = ''
        [Time]
        SaveIntervalSec=15min
      '';
    };
    tailscale.port = 6627;
    nylon = {
      enable = true;
      overlay = {
        ipv4Subnet = "10.250.10.0/24";
        ipv6Subnet = "fd10:250:10::/64";
        nat.enable = false;
      };
      routeBatch.enable = false;
      exits.public.label = 100;
    };
  };

  nix.settings = {
    min-free = 1024 * 1024 * 1024;
    max-free = 2 * 1024 * 1024 * 1024;
  };

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}
