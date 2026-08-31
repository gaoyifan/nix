{...}: {
  imports = [
    ../../optional/vm-oracle-cloud.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "oracle3";
    nameservers = ["169.254.169.254"];
  };

  systemd.network = {
    links."10-wan" = {
      matchConfig.Path = "pci-0000:00:03.0";
      linkConfig.Name = "ens3";
    };
    networks."10-wan" = {
      matchConfig.Name = "ens3";
      dhcpV4Config.UseDNS = false;
      dhcpV6Config.UseDNS = false;
      ipv6AcceptRAConfig.UseDNS = false;
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

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}
