{pkgs}:
pkgs.buildUBoot {
  version = "2026.10-rc2";
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "u-boot";
    rev = "ef064173324d9fc28e20e951ad97b6bc95101499";
    hash = "sha256-GOqzVWGdWu8yRliBTwApvbK5vj9MOSuccVWMdwwuPWE=";
  };
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
