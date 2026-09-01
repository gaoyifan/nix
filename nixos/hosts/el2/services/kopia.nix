{
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    pkgs.kopia
    pkgs.rclone
  ];

  systemd.services.kopia-alipan-maintenance = {
    description = "Run full maintenance for the Aliyun Drive Kopia repository";
    requires = ["podman-openlist.service"];
    after = ["podman-openlist.service"];
    path = [pkgs.rclone];
    serviceConfig = {
      Type = "oneshot";
      User = "yifan";
      Group = "users";
      Environment = "HOME=/home/yifan";
      ExecStart = "${lib.getExe pkgs.kopia} --config-file=/home/yifan/.config/kopia.alipan/repository.config maintenance run --full";
    };
  };

  systemd.services.kopia-alipan-snapshot = {
    description = "Back up pool0/backup and pool0/footage to Aliyun Drive with Kopia";
    requires = ["podman-openlist.service"];
    after = ["podman-openlist.service"];
    path = [pkgs.rclone];
    unitConfig.RequiresMountsFor = [
      "/pool0/backup"
      "/pool0/footage"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "yifan";
      Group = "users";
      Environment = "HOME=/home/yifan";
    };
    script = ''
      set -euo pipefail
      test "$(${lib.getExe' pkgs.util-linux "findmnt"} -rn -o SOURCE,FSTYPE --mountpoint /pool0/backup)" = "pool0/backup zfs"
      test "$(${lib.getExe' pkgs.util-linux "findmnt"} -rn -o SOURCE,FSTYPE --mountpoint /pool0/footage)" = "pool0/footage zfs"
      exec ${lib.getExe pkgs.kopia} --config-file=/home/yifan/.config/kopia.alipan/repository.config snapshot create --all
    '';
  };

  systemd.timers.kopia-alipan-maintenance = {
    wantedBy = ["el2-services.target"];
    timerConfig = {
      OnCalendar = "*-*-* 01:17:00";
      Persistent = true;
    };
  };

  systemd.timers.kopia-alipan-snapshot = {
    wantedBy = ["el2-services.target"];
    timerConfig = {
      OnCalendar = "*-*-* 02:17:00";
      Persistent = true;
    };
  };
}
