{...}: {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ../../optional/vm-oracle-cloud.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "oracle";
    edgeFirewall.enable = true;
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
