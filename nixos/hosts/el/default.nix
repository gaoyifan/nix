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

  virtualisation.vmware.guest = {
    enable = true;
    headless = true;
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  system.stateVersion = "26.05";
}
