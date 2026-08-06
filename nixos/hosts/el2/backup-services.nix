{
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    pkgs.kopia
    pkgs.rclone
  ];

  virtualisation.oci-containers.containers = {
    restic-server = {
      autoStart = false;
      image = "docker.io/restic/rest-server:latest";
      user = "1000";
      environment.DISABLE_AUTHENTICATION = "1";
      volumes = ["/pool0/restic:/data"];
      extraOptions = ["--network=host"];
    };

    restic-115-backend = {
      autoStart = false;
      image = "ghcr.io/gaoyifan/restic-115:latest";
      environment = {
        LISTEN_ADDR = "0.0.0.0";
        LISTEN_PORT = "8000";
        RUST_LOG = "info";
        DB_PATH = "/app/cache/cache-115.db";
      };
      environmentFiles = ["/pool0/docker/restic-sync-115/backend.env"];
      volumes = ["/pool0/docker/restic-sync-115/cache:/app/cache"];
      extraOptions = [
        "--network=restic-sync"
        "--network-alias=backend-115"
      ];
    };

    restic-115-sync = {
      autoStart = false;
      image = "ghcr.io/gaoyifan/restic-sync:latest";
      dependsOn = ["restic-115-backend"];
      environment = {
        REST_SYNC_SOURCE = "http://host.containers.internal:8000/";
        REST_SYNC_DEST = "http://backend-115:8000";
        REST_SYNC_CRON = "0 50 * * * *";
        RUST_LOG = "info";
      };
      extraOptions = ["--network=restic-sync"];
    };

    restic-123pan-backend = {
      autoStart = false;
      image = "ghcr.io/gaoyifan/restic-123pan@sha256:97470ece224bb71913bf93be105abcf4feab4be288b4af94da8cc36f89470328";
      environment = {
        LISTEN_ADDR = "0.0.0.0";
        LISTEN_PORT = "8000";
        RUST_LOG = "info";
        DB_PATH = "/app/cache/cache-123pan.db";
      };
      environmentFiles = ["/pool0/docker/restic-sync-123pan/backend.env"];
      volumes = ["/pool0/docker/restic-sync-123pan/cache:/app/cache"];
      extraOptions = [
        "--network=restic-sync"
        "--network-alias=backend-123pan"
      ];
    };

    restic-123pan-sync = {
      autoStart = false;
      image = "ghcr.io/gaoyifan/restic-sync:latest";
      dependsOn = ["restic-123pan-backend"];
      environment = {
        REST_SYNC_SOURCE = "http://host.containers.internal:8000/";
        REST_SYNC_DEST = "http://backend-123pan:8000";
        REST_SYNC_CRON = "0 20 * * * *";
        RUST_LOG = "info";
      };
      extraOptions = ["--network=restic-sync"];
    };
  };

  systemd.services.podman-network-restic-sync = {
    description = "Create the Restic sync Podman network";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.podman}/bin/podman network create --ignore restic-sync";
    };
  };

  systemd.services.podman-restic-server = {
    wantedBy = ["multi-user.target"];
    requires = ["zfs-mount.service"];
    after = ["zfs-mount.service"];
  };

  systemd.services.podman-restic-115-backend = {
    wantedBy = ["el2-services.target"];
    requires = [
      "mount-el2-encrypted-datasets.service"
      "podman-network-restic-sync.service"
    ];
    after = [
      "mount-el2-encrypted-datasets.service"
      "podman-network-restic-sync.service"
    ];
  };
  systemd.services.podman-restic-115-sync = {
    wantedBy = ["el2-services.target"];
    requires = ["podman-network-restic-sync.service"];
    after = [
      "podman-network-restic-sync.service"
      "podman-restic-server.service"
    ];
  };
  systemd.services.podman-restic-123pan-backend = {
    wantedBy = ["el2-services.target"];
    requires = [
      "mount-el2-encrypted-datasets.service"
      "podman-network-restic-sync.service"
    ];
    after = [
      "mount-el2-encrypted-datasets.service"
      "podman-network-restic-sync.service"
    ];
  };
  systemd.services.podman-restic-123pan-sync = {
    wantedBy = ["el2-services.target"];
    requires = ["podman-network-restic-sync.service"];
    after = [
      "podman-network-restic-sync.service"
      "podman-restic-server.service"
    ];
  };

  systemd.services.kopia-alipan-maintenance = {
    description = "Run full maintenance for the Aliyun Drive Kopia repository";
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
    requires = ["podman-openlist.service"];
    after = ["podman-openlist.service"];
    timerConfig = {
      OnCalendar = "*-*-* 01:17:00";
      Persistent = true;
    };
  };

  systemd.timers.kopia-alipan-snapshot = {
    wantedBy = ["el2-services.target"];
    requires = ["podman-openlist.service"];
    after = ["podman-openlist.service"];
    timerConfig = {
      OnCalendar = "*-*-* 02:17:00";
      Persistent = true;
    };
  };

  services.znapzend = {
    enable = true;
    logLevel = "warning";
    mailErrorSummaryTo = "znapzend@yfgao.com";
    features = {
      sendRaw = true;
      zfsGetType = true;
    };
    zetup.kingdee = {
      dataset = "pool1/incus/virtual-machines/kingdee.block";
      plan = "1hours=>10minutes,1days=>8hours,30days=>7days";
      destinations."0" = {
        host = "root@nfs.s.gaof.net";
        dataset = "pool0/pve-backup/vm-200-disk-0";
        plan = "1hours=>10minutes,1days=>8hours,30days=>7days";
      };
    };
  };

  services.restic.backups.shared-repository-prune = {
    environmentFile = "/home/yifan/nix/secrets/files/home/restic-env";
    backupPrepareCommand = ''
      #!${pkgs.runtimeShell}
      ${lib.getExe' pkgs.coreutils "install"} -d -m 0700 -o root -g root /pool0/restic-prune-tmp
    '';
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 12"
    ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 04:30:00";
      RandomizedDelaySec = "30m";
      Persistent = false;
    };
  };

  systemd.services.znapzend = {
    after = ["zfs-import-pool1.service"];
    requires = ["zfs-import-pool1.service"];
    preStart = lib.mkBefore ''
      zfs set org.znapzend:enabled=off pool0/backup pool0/footage
    '';
  };
}
