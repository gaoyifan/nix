{username, ...}: {
  imports = [
    ../../optional/bare-metal.nix
    ./disk-config.nix
    ./networking.nix
  ];

  boot = {
    # The root NVMe drive sits behind Intel VMD.
    initrd.availableKernelModules = ["vmd"];
    kernelModules = ["kvm-intel"];
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };
  hardware = {
    cpu.intel.updateMicrocode = true;
    # Required by the RTL8821CE Wi-Fi adapter.
    enableRedistributableFirmware = true;
  };

  services.tailscale.gnetMode = "client";

  home-manager.users.${username}.services.mutagen.dotfileSync.enable = false;

  system.stateVersion = "26.05";
}
