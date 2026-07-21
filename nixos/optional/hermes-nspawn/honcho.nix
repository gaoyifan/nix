{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-nspawn;
  honcho = cfg.honcho;
  honchoImage = "ghcr.io/plastic-labs/honcho:v3.0.12@sha256:1e9dbc40136d3f9213ce7482b0eecac914b630ee3e714ea961bd763945f94be5";
  litellmImage = "docker.litellm.ai/berriai/litellm:v1.93.0@sha256:a1745e629abfb17d434426ff48b115f54f4f4c4a0f5af241de569e93c63c411e";
  runtimeEnvironmentFile = "/run/honcho/env";
  postgresqlSocket = "/run/postgresql";
  model = "gpt-5.6-luna";
  embeddingModel = "Qwen/Qwen3-Embedding-8B";
  healthCheck = pkgs.writeText "honcho-healthcheck.py" ''
    import socket
    import sys

    with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=2):
        pass
  '';
  healthCommand = host: port: "/app/.venv/bin/python /etc/honcho/healthcheck.py ${host} ${toString port}";
  healthOptions = host: port: [
    "--health-cmd=${healthCommand host port}"
    "--health-interval=1m"
    "--health-timeout=3s"
    "--health-retries=3"
    "--health-startup-cmd=${healthCommand host port}"
    "--health-startup-interval=2s"
    "--health-startup-timeout=3s"
    "--health-startup-retries=60"
  ];
in {
  options.services.hermes-nspawn.honcho = {
    newApiTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "NewAPI token used by the shared Honcho backend.";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Honcho API HTTP port.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_15;
      extensions = postgresqlPackages: [postgresqlPackages.pgvector];
      ensureDatabases = ["honcho"];
      ensureUsers = [
        {
          name = "honcho";
          ensureDBOwnership = true;
        }
      ];
      authentication = lib.mkBefore ''
        local honcho honcho trust
      '';
    };

    services.redis.servers.honcho = {
      enable = true;
      bind = "127.0.0.1";
      port = 6379;
    };

    systemd.services = {
      postgresql-setup.postStart = ''
        psql \
          --dbname=honcho \
          --set=ON_ERROR_STOP=1 \
          --command='CREATE EXTENSION IF NOT EXISTS vector'
      '';

      honcho-runtime-env = {
        description = "Prepare the Honcho runtime environment";
        restartTriggers = [honcho.newApiTokenFile];
        path = [
          pkgs.coreutils
          pkgs.openssl
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "honcho";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "honcho";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
        };
        script = ''
          set -euo pipefail

          jwt_secret_file=/var/lib/honcho/jwt-secret
          if [[ ! -s "$jwt_secret_file" ]]; then
            openssl rand -hex 32 > "$jwt_secret_file"
            chmod 0600 "$jwt_secret_file"
          fi

          jwt_secret="$(tr -d '\r\n' < "$jwt_secret_file")"
          newapi_token="$(tr -d '\r\n' < ${honcho.newApiTokenFile})"
          if [[ -z "$newapi_token" ]]; then
            echo "Honcho NewAPI token is empty" >&2
            exit 1
          fi

          env_tmp=${runtimeEnvironmentFile}.tmp
          install -m 0600 /dev/null "$env_tmp"
          printf '%s\n' \
            'DB_CONNECTION_URI=postgresql+psycopg://honcho@/honcho?host=${postgresqlSocket}' \
            'CACHE_ENABLED=true' \
            'CACHE_URL=redis://127.0.0.1:6379/0?suppress=true' \
            'AUTH_USE_AUTH=true' \
            "AUTH_JWT_SECRET=$jwt_secret" \
            "LLM_OPENAI_API_KEY=$newapi_token" \
            'LLM_OPENAI_BASE_URL=http://127.0.0.1:4000/v1' \
            'DERIVER_MODEL_CONFIG__TRANSPORT=openai' \
            'DERIVER_MODEL_CONFIG__MODEL=${model}' \
            'DIALECTIC_LEVELS__minimal__MODEL_CONFIG__TRANSPORT=openai' \
            'DIALECTIC_LEVELS__minimal__MODEL_CONFIG__MODEL=${model}' \
            'DIALECTIC_LEVELS__low__MODEL_CONFIG__TRANSPORT=openai' \
            'DIALECTIC_LEVELS__low__MODEL_CONFIG__MODEL=${model}' \
            'DIALECTIC_LEVELS__medium__MODEL_CONFIG__TRANSPORT=openai' \
            'DIALECTIC_LEVELS__medium__MODEL_CONFIG__MODEL=${model}' \
            'DIALECTIC_LEVELS__high__MODEL_CONFIG__TRANSPORT=openai' \
            'DIALECTIC_LEVELS__high__MODEL_CONFIG__MODEL=${model}' \
            'DIALECTIC_LEVELS__max__MODEL_CONFIG__TRANSPORT=openai' \
            'DIALECTIC_LEVELS__max__MODEL_CONFIG__MODEL=${model}' \
            'SUMMARY_MODEL_CONFIG__TRANSPORT=openai' \
            'SUMMARY_MODEL_CONFIG__MODEL=${model}' \
            'DREAM_DEDUCTION_MODEL_CONFIG__TRANSPORT=openai' \
            'DREAM_DEDUCTION_MODEL_CONFIG__MODEL=${model}' \
            'DREAM_INDUCTION_MODEL_CONFIG__TRANSPORT=openai' \
            'DREAM_INDUCTION_MODEL_CONFIG__MODEL=${model}' \
            'EMBED_MESSAGES=true' \
            'EMBEDDING_MODEL_CONFIG__TRANSPORT=openai' \
            'EMBEDDING_MODEL_CONFIG__MODEL=${embeddingModel}' \
            'EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL=http://127.0.0.1:3000/v1' \
            'EMBEDDING_VECTOR_DIMENSIONS=4096' \
            > "$env_tmp"
          mv -f "$env_tmp" ${runtimeEnvironmentFile}
        '';
      };

      honcho-database-init = {
        description = "Initialize the Honcho database";
        after = [
          "honcho-runtime-env.service"
          "postgresql-setup.service"
        ];
        requires = [
          "honcho-runtime-env.service"
          "postgresql-setup.service"
        ];
        path = [config.virtualisation.podman.package];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        unitConfig.RequiresMountsFor = postgresqlSocket;
        script = ''
          set -euo pipefail

          podman run --rm --pull=missing --network=host \
            --env-file=${runtimeEnvironmentFile} \
            --volume=${postgresqlSocket}:${postgresqlSocket}:ro \
            --entrypoint=/app/.venv/bin/python \
            ${lib.escapeShellArg honchoImage} scripts/provision_db.py

          # pgvector HNSW indexes support at most 2,000 dimensions. The selected
          # embedding model uses 4,096, so keep exact vector search instead.
          ${config.services.postgresql.finalPackage}/bin/psql \
            --dbname=honcho \
            --username=honcho \
            --set=ON_ERROR_STOP=1 \
            --command='DROP INDEX IF EXISTS ix_documents_embedding_hnsw, ix_message_embeddings_embedding_hnsw'

          podman run --rm --pull=missing --network=host \
            --env-file=${runtimeEnvironmentFile} \
            --volume=${postgresqlSocket}:${postgresqlSocket}:ro \
            --entrypoint=/app/.venv/bin/python \
            ${lib.escapeShellArg honchoImage} scripts/configure_embeddings.py --yes
        '';
      };

      podman-honcho-api = {
        after = [
          "honcho-database-init.service"
          "redis-honcho.service"
        ];
        requires = [
          "honcho-database-init.service"
          "redis-honcho.service"
        ];
        restartTriggers = [honcho.newApiTokenFile];
      };

      podman-honcho-deriver = {
        restartTriggers = [honcho.newApiTokenFile];
      };
    };

    virtualisation.oci-containers.containers = {
      honcho-openai-bridge = {
        image = litellmImage;
        entrypoint = "/app/.venv/bin/python";
        cmd = [
          "-m"
          "uvicorn"
          "honcho_openai_bridge:app"
          "--host"
          "127.0.0.1"
          "--port"
          "4000"
        ];
        volumes = [
          "${./honcho-openai-bridge.py}:/app/honcho_openai_bridge.py:ro"
          "${healthCheck}:/etc/honcho/healthcheck.py:ro"
        ];
        environment = {
          NEWAPI_BASE_URL = "http://127.0.0.1:3000/v1";
          PYTHONUNBUFFERED = "1";
        };
        dependsOn = ["new-api"];
        extraOptions =
          ["--network=host"]
          ++ healthOptions "127.0.0.1" 4000;
        podman.sdnotify = "healthy";
      };

      honcho-api = {
        image = honchoImage;
        entrypoint = "/app/.venv/bin/fastapi";
        cmd = [
          "run"
          "--host"
          cfg.listenAddress
          "--port"
          (toString honcho.apiPort)
          "src/main.py"
        ];
        workdir = "/app";
        volumes = [
          "${healthCheck}:/etc/honcho/healthcheck.py:ro"
          "${postgresqlSocket}:${postgresqlSocket}:ro"
        ];
        environmentFiles = [runtimeEnvironmentFile];
        dependsOn = ["honcho-openai-bridge"];
        extraOptions =
          ["--network=host"]
          ++ healthOptions cfg.listenAddress honcho.apiPort;
        podman.sdnotify = "healthy";
      };

      honcho-deriver = {
        image = honchoImage;
        entrypoint = "/app/.venv/bin/python";
        cmd = ["-m" "src.deriver"];
        workdir = "/app";
        volumes = [
          "${postgresqlSocket}:${postgresqlSocket}:ro"
        ];
        environmentFiles = [runtimeEnvironmentFile];
        dependsOn = ["honcho-api"];
        extraOptions = ["--network=host"];
      };
    };

    networking.nftables.tables.honcho = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter;
          iifname { ${lib.concatMapStringsSep ", " (interface: ''"${interface}"'') cfg.allowedInterfaces} } tcp dport ${toString honcho.apiPort} accept
          tcp dport ${toString honcho.apiPort} reject with tcp reset
        }
      '';
    };
  };
}
