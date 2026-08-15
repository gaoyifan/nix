{...}: {
  imports = [
    ../../optional/authoritative-ns.nix
    ../../optional/nylon-public-exit.nix
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./disk-config.nix
    ./networking.nix
    ./services.nix
  ];

  boot = {
    loader.grub.enable = true;
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200n8"
    ];
    zswap.enable = true;
  };

  system.stateVersion = "26.05";
}
