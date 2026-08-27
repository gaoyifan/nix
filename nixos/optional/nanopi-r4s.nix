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
  services.journald.storage = "volatile";
  # Keep Nylon's latency-sensitive dispatcher on the RK3399 Cortex-A72 cores.
  systemd.services.nylon = lib.mkIf (config.services.nylon.enable or false) {
    serviceConfig.AllowedCPUs = "4-5";
  };

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

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "update-nanopi-r4s-uboot";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "usage: update-nanopi-r4s-uboot /dev/mmcblkN" >&2
          exit 2
        fi

        device="$1"
        idbloader=${pkgs.nanopi-r4s-uboot}/idbloader.img
        uboot_itb=${pkgs.nanopi-r4s-uboot}/u-boot.itb
        idbloader_size="$(stat -c %s "$idbloader")"
        uboot_itb_size="$(stat -c %s "$uboot_itb")"

        if cmp -s "$idbloader" \
          <(dd if="$device" skip=$((64 * 512)) count="$idbloader_size" iflag=skip_bytes,count_bytes status=none) && \
          cmp -s "$uboot_itb" \
          <(dd if="$device" skip=$((16384 * 512)) count="$uboot_itb_size" iflag=skip_bytes,count_bytes status=none); then
          echo "$device already contains ${pkgs.nanopi-r4s-uboot.name}"
          exit 0
        fi

        backup_dir=/var/lib/nanopi-r4s-uboot/backups
        install -d -m 0700 "$backup_dir"
        backup="$backup_dir/$(date -u +%Y%m%dT%H%M%SZ)-$(basename "$device")-first-16MiB.img"
        dd if="$device" of="$backup" bs=1M count=16 iflag=fullblock conv=fsync status=none
        chmod 0600 "$backup"
        echo "backed up the first 16 MiB to $backup"

        dd if="$idbloader" of="$device" bs=512 seek=64 conv=notrunc,fsync status=none
        dd if="$uboot_itb" of="$device" bs=512 seek=16384 conv=notrunc,fsync status=none
        sync "$device"

        cmp "$idbloader" \
          <(dd if="$device" skip=$((64 * 512)) count="$idbloader_size" iflag=skip_bytes,count_bytes status=none)
        cmp "$uboot_itb" \
          <(dd if="$device" skip=$((16384 * 512)) count="$uboot_itb_size" iflag=skip_bytes,count_bytes status=none)
        echo "updated $device to ${pkgs.nanopi-r4s-uboot.name}"
      '';
    })
  ];

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

  nix = {
    settings.max-jobs = 0;
    distributedBuilds = true;
    buildMachines = [
      {
        protocol = "ssh-ng";
        sshUser = "yifan";
        hostName = "100.127.101.9?remote-program=/run/current-system/sw/bin/nix-daemon";
        system = "aarch64-linux";
        maxJobs = 4;
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBuVENJd3dGSUJ0ZmZVTmd0TG5Yb0FFc0dtbFYxVnJHd1VMVHhtME5HSVQ=";
      }
    ];
  };
}
