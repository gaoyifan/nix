# somo-nanopi-r4s - NanoPi R4S staged replacement for the SOMO gateway.
{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    (modulesPath + "/installer/sd-card/sd-image.nix")
    ./networking.nix
    ./tailscale.nix
    ./wg-el2.nix
  ];

  boot = {
    consoleLogLevel = lib.mkDefault 7;
    initrd.kernelModules = ["rtc-rk808"];
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
  };

  hardware.enableRedistributableFirmware = true;

  image.baseName = "somo-nanopi-r4s";
  sdImage = {
    # U-Boot lives at 8 MiB, so keep both partitions beyond it.
    firmwarePartitionOffset = 16;
    populateFirmwareCommands = "";
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

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  nix.settings = {
    max-jobs = 2;
    substituters = lib.mkForce [
      "http://nix-cache.lib.ustc.edu.cn:8501"
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://nix-cache.yfgao.net?priority=50"
      "https://cache.nixos.org?priority=100"
    ];
    trusted-public-keys = [
      "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
    ];
  };

  system.stateVersion = "26.05";
}
