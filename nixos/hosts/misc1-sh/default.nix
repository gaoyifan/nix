{...}: {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/el2-derp-bootstrap.nix
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./disk-config.nix
    ./networking.nix
  ];

  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  networking.edgeFirewall.enable = true;

  system.stateVersion = "26.05";
}
