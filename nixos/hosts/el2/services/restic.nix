{
  config,
  inputs,
  lib,
  pkgs,
  username,
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

  services.resticBackup = {
    extraPaths = ["/var/lib/wireguard"];
    extraExcludes = ["!/home/${username}/.syncd-dotfiles"];
  };

  networking.edgeFirewall.extraInputRules = [''iifname "podman*" tcp dport 8000 accept''];

  virtualisation.oci-containers.containers = {
    restic-server = {
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
      cacheDirectory = "/pool1/services/restic-sync-115/cache";
      listenPort = 8001;
      user = "yifan";
      group = "users";
    };
    instances.restic-backup-b128 = {
      repositoryPath = "/restic-backup-b128";
      cacheDirectory = "/pool1/services/restic-115/restic-backup-b128";
      listenPort = 8006;
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
      cacheDirectory = "/pool1/services/restic-sync-123pan/cache";
      listenPort = 8002;
      user = "yifan";
      group = "users";
    };
    instances.restic-backup = {
      usernameFile = "/run/agenix/restic-123pan-username";
      passwordFile = "/run/agenix/restic-123pan-password";
      repositoryPath = "/restic-backup";
      cacheDirectory = "/pool1/services/restic-123pan/restic-backup";
      listenPort = 8005;
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
    requires = ["zfs-mount.service"];
    after = ["zfs-mount.service"];
  };

  systemd.services.restic-115-pool0-restic = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };
  systemd.services.restic-123pan-pool0-restic = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };

  systemd.timers.restic-sync-115.wantedBy = lib.mkForce ["el2-services.target"];
  systemd.timers.restic-sync-123pan.wantedBy = lib.mkForce ["el2-services.target"];

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
}
