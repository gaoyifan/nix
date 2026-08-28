{username, ...}: {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "oracle";
    nameservers = ["169.254.169.254"];
    useDHCP = false;
    useNetworkd = true;
    edgeFirewall = {
      enable = true;
      extraPublicUdpPorts = [
        "3334"
      ];
    };
  };

  systemd.network = {
    links."10-wan" = {
      matchConfig.Path = "pci-0000:00:03.0";
      linkConfig.Name = "ens3";
    };
    networks."10-wan" = {
      matchConfig.Name = "ens3";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  boot = {
    loader.grub = {
      enable = true;
      device = "nodev";
      efiInstallAsRemovable = true;
      efiSupport = true;
    };
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200n8"
    ];
    zswap.enable = true;
  };

  users.users.${username}.uid = 1000;

  virtualisation = {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers.bitmagnet = {
        image = "docker.io/gaoyifan/bitmagnet:dev";
        cmd = [
          "worker"
          "run"
          "--keys=queue_server"
          "--keys=dht_crawler"
        ];
        environmentFiles = ["/var/lib/bitmagnet-crawler/env"];
        extraOptions = [
          "--network=host"
          "--cpu-shares=128"
        ];
      };
    };
  };

  services = {
    journald.extraConfig = "SystemMaxUse=256M";
  };

  services.resticBackup.extraPaths = ["/var/lib/bitmagnet-crawler"];

  systemd.tmpfiles.rules = ["d /var/lib/bitmagnet-crawler 0700 root root -"];

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}
