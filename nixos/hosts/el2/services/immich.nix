{
  config,
  lib,
  pkgs,
  ...
}: let
  immichDatabaseEnvironmentFile = "/run/agenix/immich-database-env";
in {
  age.secrets.immich-database-env = lib.mkIf config.services.secrets.hasRealFiles {
    file = config.services.secrets.filesDir + "/nixos/el2/immich-database-env.age";
  };

  virtualisation.oci-containers.containers = {
    immich-postgres = {
      autoStart = false;
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
      environment = {
        POSTGRES_DB = "immich";
        POSTGRES_INITDB_ARGS = "--data-checksums";
        POSTGRES_USER = "postgres";
        DB_STORAGE_TYPE = "SSD";
      };
      environmentFiles = [immichDatabaseEnvironmentFile];
      volumes = ["/pool1/services/immich-postgres:/var/lib/postgresql/data"];
      extraOptions = [
        "--network=immich"
        "--network-alias=database"
        "--shm-size=128m"
      ];
    };

    immich-redis = {
      autoStart = false;
      image = "docker.io/valkey/valkey:9@sha256:8e8d64b405ce18f41b8e5ee20aa4687a8ed0022d1298f2ce31cdcf3a76e09411";
      extraOptions = [
        "--network=immich"
        "--network-alias=redis"
      ];
    };

    immich-server = {
      autoStart = false;
      image = "ghcr.io/immich-app/immich-server:v3.1.0";
      dependsOn = [
        "immich-postgres"
        "immich-redis"
      ];
      environment = {
        TZ = "Asia/Shanghai";
        DB_HOSTNAME = "database";
        DB_USERNAME = "postgres";
        DB_DATABASE_NAME = "immich";
        REDIS_HOSTNAME = "redis";
        IMMICH_MACHINE_LEARNING_URL = "http://100.127.110.112:3003";
      };
      environmentFiles = [immichDatabaseEnvironmentFile];
      ports = ["127.0.0.1:2283:2283"];
      volumes = [
        "/pool1/services/immich/library:/data"
        "/pool0/footage:/mnt/media/footage:ro"
        "/etc/localtime:/etc/localtime:ro"
      ];
      extraOptions = ["--network=immich"];
    };
  };

  systemd.services.podman-network-immich = {
    description = "Create the Immich Podman network";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.podman}/bin/podman network create --ignore immich";
    };
  };

  systemd.services.podman-immich-postgres = {
    wantedBy = ["el2-services.target"];
    requires = [
      "zfs-unlock-mount.service"
      "podman-network-immich.service"
    ];
    after = [
      "zfs-unlock-mount.service"
      "podman-network-immich.service"
    ];
  };

  systemd.services.podman-immich-redis = {
    wantedBy = ["el2-services.target"];
    requires = ["podman-network-immich.service"];
    after = ["podman-network-immich.service"];
  };

  systemd.services.podman-immich-server = {
    wantedBy = ["el2-services.target"];
    requires = [
      "zfs-unlock-mount.service"
      "podman-network-immich.service"
    ];
    after = [
      "zfs-unlock-mount.service"
      "podman-network-immich.service"
    ];
  };
}
