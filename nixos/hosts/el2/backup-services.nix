{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    inputs.restic-115.nixosModules.default
    inputs.restic-123pan.nixosModules.default
    inputs.restic-sync.nixosModules.default
  ];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    restic-115-access-token.file = config.services.secrets.filesDir + "/nixos/el2/restic-115-access-token.age";
    restic-115-refresh-token.file = config.services.secrets.filesDir + "/nixos/el2/restic-115-refresh-token.age";
    restic-123pan-username.file = config.services.secrets.filesDir + "/nixos/el2/restic-123pan-username.age";
    restic-123pan-password.file = config.services.secrets.filesDir + "/nixos/el2/restic-123pan-password.age";
    restic-backups-shared-repository-password.file = config.services.secrets.filesDir + "/nixos/el2/restic-backups-shared-repository-password.age";
  };

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
  };

  services.restic-115 = {
    enable = true;
    instances.pool0-restic = {
      accessTokenFile = "/run/agenix/restic-115-access-token";
      refreshTokenFile = "/run/agenix/restic-115-refresh-token";
      repositoryPath = "/pool0-restic";
      cacheDirectory = "/pool0/docker/restic-sync-115/cache";
      listenPort = 8001;
      user = "yifan";
      group = "users";
    };
  };

  services.restic-123pan = {
    enable = true;
    instances.pool0-restic = {
      usernameFile = "/run/agenix/restic-123pan-username";
      passwordFile = "/run/agenix/restic-123pan-password";
      repositoryPath = "/pool0-restic";
      cacheDirectory = "/pool0/docker/restic-sync-123pan/cache";
      listenPort = 8002;
      user = "yifan";
      group = "users";
    };
  };

  services.restic-sync = {
    enable = true;
    instances = {
      "115" = {
        source = "http://127.0.0.1:8000/";
        destination = "http://127.0.0.1:8001/";
        schedule = "*-*-* *:50:00";
        user = "yifan";
        group = "users";
        dependsOn = [
          "podman-restic-server.service"
          "restic-115-pool0-restic.service"
        ];
      };
      "123pan" = {
        source = "http://127.0.0.1:8000/";
        destination = "http://127.0.0.1:8002/";
        schedule = "*-*-* *:20:00";
        user = "yifan";
        group = "users";
        dependsOn = [
          "podman-restic-server.service"
          "restic-123pan-pool0-restic.service"
        ];
      };
    };
  };

  systemd.services.podman-restic-server = {
    wantedBy = ["multi-user.target"];
    requires = ["zfs-mount.service"];
    after = ["zfs-mount.service"];
  };

  systemd.services.restic-115-pool0-restic = {
    wantedBy = ["el2-services.target"];
    requires = ["mount-el2-encrypted-datasets.service"];
    after = ["mount-el2-encrypted-datasets.service"];
  };
  systemd.services.restic-123pan-pool0-restic = {
    wantedBy = ["el2-services.target"];
    requires = ["mount-el2-encrypted-datasets.service"];
    after = ["mount-el2-encrypted-datasets.service"];
  };

  systemd.timers.restic-sync-115.wantedBy = lib.mkForce ["el2-services.target"];
  systemd.timers.restic-sync-123pan.wantedBy = lib.mkForce ["el2-services.target"];

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
    repository = "rest:http://restic-nas.ts.gaof.net/";
    passwordFile = "/run/agenix/restic-backups-shared-repository-password";
    backupPrepareCommand = ''
      #!${pkgs.runtimeShell}
      ${lib.getExe' pkgs.coreutils "install"} -d -m 0700 -o root -g root /pool0/restic-prune-tmp
    '';
    pruneOpts = [
      "--pack-size 128"
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
