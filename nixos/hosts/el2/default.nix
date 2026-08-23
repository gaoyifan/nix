{
  pkgs,
  username,
  ...
}: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./backup-services.nix
    ./media-services.nix
    ./mutagen-sync.nix
    ./networking.nix
    ./services.nix
    ./tailscale.nix
    ./virtualisation.nix
    ./wg0.nix
    ./xu2hao.nix
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
  boot.zfs.requestEncryptionCredentials = false;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0YEmRhF27t46boAwcyDGn1VrEuK9ydNhu24o7RO4Sr root@nfs"
  ];

  environment.systemPackages = [pkgs.mbuffer];

  services.resticBackup = {
    extraPaths = ["/var/lib/wireguard"];
    extraExcludes = ["!/home/${username}/.syncd-dotfiles"];
  };

  systemd.targets.el2-services = {
    description = "Services using manually unlocked datasets";
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };

  system.stateVersion = "26.05";
}
