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
  version = "3.5.1-fork-74ec7f59";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "htop";
    rev = "74ec7f59c7391f72c140fa2d101d1192ec985a35";
    hash = "sha256-X7GOJdxW/pjdLl6tN14xZPG87gkOwyF3sbr20wX2AUQ=";
  };
}
