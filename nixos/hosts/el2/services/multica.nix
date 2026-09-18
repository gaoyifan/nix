{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  dataDirectory = "/var/lib/multica";
  backendEnvironmentFile = "/run/agenix/multica-backend-env";
  postgresEnvironmentFile = "/run/agenix/multica-postgres-env";
  hasSecrets = config.services.secrets.hasRealFiles;
  backendPort = 18080;
  frontendPort = 13000;
  frontendOrigin = "http://localhost:${toString frontendPort}";
  serverUrl = "http://127.0.0.1:${toString backendPort}";
  multicaEnvironment = {
    MULTICA_APP_URL = frontendOrigin;
    MULTICA_SERVER_URL = serverUrl;
    MULTICA_WORKSPACES_ROOT = "${dataDirectory}/workspaces";
  };
in {
  age.secrets = lib.mkIf hasSecrets {
    multica-backend-env.file = config.services.secrets.filesDir + "/nixos/el2/multica-backend-env.age";
    multica-postgres-env.file = config.services.secrets.filesDir + "/nixos/el2/multica-postgres-env.age";
  };

  virtualisation.oci-containers.containers = {
    multica-postgres = {
      image = "docker.io/pgvector/pgvector:pg17@sha256:cf134a767f474095eeba57e0117be8e568e011a63f33fbf252f14c9b760f8e6f";
      environment = {
        POSTGRES_DB = "multica";
        POSTGRES_USER = "multica";
      };
      environmentFiles = [postgresEnvironmentFile];
      volumes = ["${dataDirectory}/postgres:/var/lib/postgresql/data"];
      networks = ["multica"];
      extraOptions = [
        "--network-alias=postgres"
        "--health-cmd=pg_isready -U multica -d multica"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=12"
      ];
      podman.sdnotify = "healthy";
    };

    multica-backend = {
      image = "ghcr.io/multica-ai/multica-backend:v0.5.0@sha256:37d84b685068f073b09d624eeabbb95df97df3878233f03b14f350210e101de4";
      dependsOn = ["multica-postgres"];
      environment = {
        ANALYTICS_DISABLED = "true";
        APP_ENV = "production";
        DO_NOT_TRACK = "true";
        FRONTEND_ORIGIN = frontendOrigin;
        MULTICA_DAEMON_SERVER_URL = serverUrl;
      };
      environmentFiles = [backendEnvironmentFile];
      ports = ["0.0.0.0:${toString backendPort}:8080"];
      volumes = ["${dataDirectory}/uploads:/app/data/uploads"];
      networks = ["multica"];
      extraOptions = ["--network-alias=backend"];
    };

    multica-frontend = {
      image = "ghcr.io/multica-ai/multica-web:v0.5.0@sha256:bf2ad41369cb1b37a0b62ae6ac8fd62a8e23636332f716bc579399ca725086f5";
      dependsOn = ["multica-backend"];
      ports = ["0.0.0.0:${toString frontendPort}:3000"];
      networks = ["multica"];
    };
  };

  systemd.tmpfiles.settings."10-multica" = {
    "${dataDirectory}".d = {
      mode = "0750";
      user = "root";
      group = "users";
    };
    "${dataDirectory}/workspaces".d = {
      mode = "0750";
      user = username;
      group = "users";
    };
  };

  systemd.services = {
    podman-network-multica = {
      description = "Create the Multica Podman network";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.podman}/bin/podman network create --ignore multica";
      };
    };

    podman-multica-postgres = {
      requires = ["podman-network-multica.service"];
      after = ["podman-network-multica.service"];
      restartTriggers = lib.optional hasSecrets config.age.secrets.multica-postgres-env.file;
    };

    podman-multica-backend = {
      requires = ["podman-network-multica.service"];
      after = ["podman-network-multica.service"];
      restartTriggers = lib.optional hasSecrets config.age.secrets.multica-backend-env.file;
    };

    podman-multica-frontend = {
      requires = ["podman-network-multica.service"];
      after = ["podman-network-multica.service"];
    };
  };

  home-manager.users.${username} = {
    home.sessionVariables = multicaEnvironment;
    systemd.user.sessionVariables = multicaEnvironment;

    systemd.user.services.multica-daemon = {
      Unit = {
        Description = "Multica agent daemon";
        ConditionPathExists = "%h/.multica/config.json";
      };
      Service = {
        Environment =
          lib.mapAttrsToList (name: value: "${name}=${value}") multicaEnvironment
          ++ [
            "CODEX_HOME=/home/${username}/.syncd-dotfiles/.codex"
            "PATH=${lib.makeBinPath [pkgs.multica pkgs.codex]}:/home/${username}/.nix-profile/bin:/run/current-system/sw/bin:/run/wrappers/bin"
          ];
        ExecStartPre = "${pkgs.curl}/bin/curl --fail --silent --show-error --retry 60 --retry-delay 5 --retry-connrefused ${serverUrl}/health";
        ExecStart = "${lib.getExe pkgs.multica} daemon start --foreground --device-name el2";
        Restart = "on-failure";
        RestartSec = "15s";
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
