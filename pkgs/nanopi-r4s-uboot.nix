{pkgs}:
pkgs.buildUBoot {
  defconfig = "nanopi-r4s-rk3399_defconfig";
  env.BL31 = "${pkgs.armTrustedFirmwareRK3399}/bl31.elf";
  filesToInstall = [
    "idbloader.img"
    "u-boot.itb"
  ];
  extraMeta.platforms = ["aarch64-linux"];
}
