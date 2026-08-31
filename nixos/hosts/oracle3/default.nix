{...}: {
  imports = [
    ../../optional/vm-oracle-cloud.nix
    ./disk-config.nix
  ];

  networking.hostName = "oracle3";

  systemd.network = {
    links."10-wan" = {
      matchConfig.Path = "pci-0000:00:03.0";
      linkConfig.Name = "ens3";
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

  services.journald.extraConfig = "SystemMaxUse=256M";

  system.stateVersion = "26.05";
}
