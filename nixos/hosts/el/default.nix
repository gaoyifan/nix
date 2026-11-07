{...}: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./networking.nix
    ./services.nix
    ./tailscale.nix
  ];

  networking.hostName = "el";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  virtualisation.vmware.guest.enable = true;

  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
