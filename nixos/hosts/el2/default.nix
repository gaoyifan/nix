{pkgs, ...}: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./networking.nix
    ./services.nix
    ./tailscale.nix
    ./virtualisation.nix
    ./wg-iplc.nix
    ./wg0.nix
  ];

  networking.hostName = "el2";
  networking.hostId = "e2aa9800";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Favor routing throughput over protection from CPU speculative-execution vulnerabilities.
  boot.kernelParams = ["mitigations=off"];
  # Enable runtime ZFS support and pool import; the Btrfs root initrd does not include ZFS.
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.extraPools = [
    "pool0"
    "pool1"
  ];
  boot.zfs.forceImportRoot = false;

  fileSystems."/pool1/nix-cache" = {
    device = "pool1/nix-cache";
    fsType = "zfs";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0YEmRhF27t46boAwcyDGn1VrEuK9ydNhu24o7RO4Sr root@nfs"
  ];

  environment.systemPackages = [pkgs.mbuffer];

  system.stateVersion = "26.05";
}
