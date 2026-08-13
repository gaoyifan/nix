{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}: {
  imports = [(modulesPath + "/installer/sd-card/sd-image.nix")];

  boot = {
    consoleLogLevel = lib.mkDefault 7;
    growPartition = true;
    initrd = {
      kernelModules = ["rtc-rk808"];
      supportedFilesystems = ["btrfs"];
    };
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "cma=32M"
      "console=ttyS2,115200n8"
      "console=tty0"
    ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
      timeout = 3;
    };
    supportedFilesystems = ["btrfs"];
  };

  fileSystems."/" = {
    autoResize = true;
    fsType = lib.mkForce "btrfs";
    options = ["compress=zstd:3"];
  };

  hardware.enableRedistributableFirmware = true;

  image.baseName = config.networking.hostName;
  sdImage = {
    # U-Boot lives at 8 MiB, so keep both partitions beyond it.
    firmwarePartitionOffset = 16;
    expandOnBoot = false;
    populateFirmwareCommands = "";
    rootFilesystemCreator = ./make-btrfs-fs.nix;
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} \
        -d ./files/boot
    '';
    postBuildCommands = ''
      dd if=${pkgs.nanopi-r4s-uboot}/idbloader.img of="$img" conv=notrunc bs=512 seek=64
      dd if=${pkgs.nanopi-r4s-uboot}/u-boot.itb of="$img" conv=notrunc bs=512 seek=16384
    '';
  };

  systemd.services.btrfs-boot-no-compression = {
    description = "Disable Btrfs compression for U-Boot files";
    wantedBy = ["local-fs.target"];
    after = ["systemd-remount-fs.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      find /boot -type d -exec ${lib.getExe' pkgs.btrfs-progs "btrfs"} property set {} compression none \;
    '';
  };

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  nix.settings.max-jobs = 2;
}
