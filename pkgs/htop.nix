# htop built from a personal fork that splits the multi-column CPU meter width
# across the columns actually in use, so half-meters with few cores fill the
# available space instead of leaving unused columns blank.
# Fork: https://github.com/gaoyifan/htop (commit on main).
#
# sensorsSupport = false: drop the libsensors dependency. Without it htop links
# libsensors unconditionally, and on machines lacking hardware sensors (e.g.
# cloud VMs with no /sys/class/hwmon) libsensors prints
# "/sys: No sensors at /sys/class/hwmon." to stderr on every launch.
{pkgs}:
(pkgs.htop.override {sensorsSupport = false;}).overrideAttrs {
  version = "3.5.1-fork-472cee72";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "htop";
    rev = "472cee728dd6142bab417d78b791f4d4abd57c2d";
    hash = "sha256-NzxP6U8YxTTt5ctp2aTWXtzTtD3ACKFTrRVz2gDGqX8=";
  };
}
