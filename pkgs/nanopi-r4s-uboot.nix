{pkgs}:
pkgs.buildUBoot {
  defconfig = "nanopi-r4s-rk3399_defconfig";
  extraConfig = ''
    CONFIG_BAUDRATE=115200
    CONFIG_FS_BTRFS=y
  '';
  postPatch = ''
    patchShebangs scripts tools
    substituteInPlace dts/upstream/src/arm64/rockchip/rk3399-nanopi4.dtsi \
      --replace-fail 'stdout-path = "serial2:1500000n8"' 'stdout-path = "serial2:115200n8"'
  '';
  env.BL31 = "${pkgs.armTrustedFirmwareRK3399}/bl31.elf";
  filesToInstall = [
    "idbloader.img"
    "u-boot.itb"
  ];
  extraMeta.platforms = ["aarch64-linux"];
}
