{...}: {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ../../optional/vm-oracle-cloud.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "oracle";
    nameservers = ["169.254.169.254"];
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
    networks."10-wan".matchConfig.Name = "ens3";
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

  services.resticBackup.extraPaths = ["/var/lib/bitmagnet-crawler"];

  services.journald.extraConfig = "SystemMaxUse=256M";

  systemd.tmpfiles.rules = ["d /var/lib/bitmagnet-crawler 0700 root root -"];

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}
