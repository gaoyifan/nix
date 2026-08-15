{
  modulesPath,
  username,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../optional/authoritative-ns.nix
    ../../optional/nylon-public-exit.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./disk-config.nix
    ./networking.nix
  ];

  boot = {
    loader = {
      grub = {
        enable = true;
        device = "nodev";
        efiInstallAsRemovable = true;
        efiSupport = true;
      };
    };
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200n8"
    ];
  };

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  users.users.${username}.uid = 1000;

  services.journald.extraConfig = "SystemMaxUse=256M";

  system.stateVersion = "26.05";
}
