{pkgs}:
pkgs.buildUBoot {
  version = "2026.10-rc2";
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "u-boot";
    rev = "ef064173324d9fc28e20e951ad97b6bc95101499";
    hash = "sha256-GOqzVWGdWu8yRliBTwApvbK5vj9MOSuccVWMdwwuPWE=";
  };
  defconfig = "nanopi-r5c-rk3568_defconfig";
  extraConfig = ''
    CONFIG_FS_BTRFS=y
  '';
  env = {
    BL31 = pkgs.rkbin.BL31_RK3568;
    ROCKCHIP_TPL = pkgs.rkbin.TPL_RK3568;
  };
  filesToInstall = [
    "idbloader.img"
    "u-boot.itb"
  ];
  extraMeta.platforms = ["aarch64-linux"];
}
