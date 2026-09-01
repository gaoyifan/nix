{
  lib,
  pkgs,
  ...
}: let
  encryptedDatasets = [
    "pool0/backup"
    "pool1/services"
    "pool0/footage"
    "pool0/kopia"
    "pool0/media0"
    "pool0/media1"
    "pool0/playground"
    "pool0/syncthing"
  ];
in {
  imports = [
    ../../optional/zfs-unlock.nix
    ./disk-config.nix
    ./hardware-configuration.nix
    ./services
    ./networking
    ./virtualisation.nix
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

  programs.zfsUnlock.datasets = encryptedDatasets;

  systemd.services.zfs-unlock-mount = {
    after = [
      "zfs-import-pool0.service"
      "zfs-import-pool1.service"
    ];
    requires = [
      "zfs-import-pool0.service"
      "zfs-import-pool1.service"
    ];
    preStart = ''
      ${pkgs.zfs}/bin/zfs set readonly=on pool0/backup pool0/footage
    '';
    serviceConfig.ExecStartPost = "${lib.getExe' pkgs.systemd "systemctl"} --no-ask-password --no-block start el2-services.target";
  };

  systemd.targets.el2-services = {
    description = "Services using manually unlocked datasets";
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };

  system.stateVersion = "26.05";
}
