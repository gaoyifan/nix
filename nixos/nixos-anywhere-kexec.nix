{
  config,
  lib,
  nixosImages,
  pkgs,
  ...
}: {
  disabledModules = ["${nixosImages}/nix/zfs-minimal.nix"];

  system.kexec-installer.name = "nixos-anywhere-tiny-kexec";

  system.build.kexecRun = lib.mkForce (pkgs.runCommand "nixos-anywhere-tiny-kexec-run" {} ''
    install -D -m 0755 ${nixosImages}/nix/kexec-installer/kexec-run.sh $out
    sed -i \
      -e 's|@init@|${config.system.build.toplevel}/init|' \
      -e 's|@kernelParams@|${lib.escapeShellArgs config.boot.kernelParams}|' \
      -e 's|sleep 6 && |sleep 6 \&\& cd / \&\& |' \
      $out
    ${pkgs.shellcheck}/bin/shellcheck $out
  '');

  system.disableInstallerTools = true;

  environment.systemPackages = lib.mkForce [
    config.system.build.nixos-install
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.nix
    pkgs.rsync
    pkgs.systemd
    pkgs.util-linux
  ];

  boot.supportedFilesystems = lib.mkForce [
    "btrfs"
    "vfat"
  ];
  boot.bcache.enable = false;
  boot.kernelModules = lib.mkForce [];
  boot.swraid.enable = lib.mkForce false;
  services.lvm.enable = false;

  hardware.enableAllHardware = lib.mkForce false;
  boot.initrd.availableKernelModules = lib.mkForce [
    "ahci"
    "ata_piix"
    "autofs"
    "erofs"
    "hv_storvsc"
    "loop"
    "nvme"
    "overlay"
    "sd_mod"
    "squashfs"
    "sr_mod"
    "usb_storage"
    "uas"
    "virtio_blk"
    "virtio_console"
    "virtio_mmio"
    "virtio_net"
    "virtio_pci"
    "virtio_scsi"
    "vmw_pvscsi"
    "vmxnet3"
    "xhci_pci"
  ];

  system.stateVersion = config.system.nixos.release;
}
