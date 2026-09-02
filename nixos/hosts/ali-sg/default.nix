{lib, ...}: {
  imports = [
    ../../optional/authoritative-ns
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./disk-config.nix
    ./networking.nix
    ./services.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200n8"
    ];
    zswap.enable = true;
  };

  fileSystems."/".device = lib.mkForce "/dev/disk/by-label/nixos-root";

  system.stateVersion = "26.05";
}
