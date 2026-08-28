{...}: {
  imports = [
    ../qemu-guest.nix
    ../tailscale-gnet-vm-exit.nix
    ./disk-config.nix
  ];

  networking = {
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
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
    zswap.enable = true;
  };

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 2 * 1024;
    }
  ];

  services = {
    timesyncd = {
      extraConfig = ''
        [Time]
        SaveIntervalSec=15min
      '';
    };
  };

  nix.settings = {
    min-free = 1024 * 1024 * 1024;
    max-free = 2 * 1024 * 1024 * 1024;
  };

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}
