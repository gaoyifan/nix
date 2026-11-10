{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.honcho;
  inherit (cfg) listenAddress;
  honchoImage = cfg.image;
  runtimeEnvironmentFile = "/run/honcho/env";
  postgresqlSocket = "/run/postgresql";
  healthCheck = pkgs.writeText "honcho-healthcheck.py" ''
    import json
    import sys
    from http.client import HTTPConnection

    for encoding_name in ("o200k_base", "cl100k_base"):
        import tiktoken

        tiktoken.get_encoding(encoding_name)

    connection = HTTPConnection(sys.argv[1], int(sys.argv[2]), timeout=2)
    try:
        connection.request("GET", "/health")
        response = connection.getresponse()
        if response.status != 200 or json.load(response) != {"status": "ok"}:
            raise RuntimeError(f"unhealthy response: HTTP {response.status}")
    finally:
        connection.close()
  '';
  healthCommand = "/app/.venv/bin/python /etc/honcho/healthcheck.py ${listenAddress} ${toString cfg.apiPort}";
  tiktokenO200kBase = pkgs.fetchurl {
    url = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken";
    hash = "sha256-RGqVOMtsNI41FhINfAiwn1fDZJXirP/+WaW/iwz7Gi0=";
  };
  tiktokenCl100kBase = pkgs.fetchurl {
    url = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken";
    hash = "sha256-Ijkht27pm96ZW3/3OFE+7xAPtR0YyTWXoRO8/+hlsqc=";
  };
  modelKeys = [
    "DERIVER_MODEL_CONFIG"
    "DIALECTIC_LEVELS__minimal__MODEL_CONFIG"
    "DIALECTIC_LEVELS__low__MODEL_CONFIG"
    "DIALECTIC_LEVELS__medium__MODEL_CONFIG"
    "DIALECTIC_LEVELS__high__MODEL_CONFIG"
    "DIALECTIC_LEVELS__max__MODEL_CONFIG"
    "SUMMARY_MODEL_CONFIG"
    "DREAM_DEDUCTION_MODEL_CONFIG"
    "DREAM_INDUCTION_MODEL_CONFIG"
  ];
  publicEnvironment = pkgs.writeText "honcho-env-public" (lib.generators.toKeyValue {} (
    {
      DB_CONNECTION_URI = "postgresql+psycopg://honcho@/honcho?host=${postgresqlSocket}";
      AUTH_USE_AUTH = "true";
      CACHE_ENABLED = "false";
      EMBED_MESSAGES = "true";
      EMBEDDING_MODEL_CONFIG__TRANSPORT = "openai";
      EMBEDDING_MODEL_CONFIG__MODEL = "Qwen/Qwen3-Embedding-8B";
      EMBEDDING_VECTOR_DIMENSIONS = "4096";
    }
    // lib.listToAttrs (lib.concatMap (key: [
        {
          name = "${key}__TRANSPORT";
          value = "openai";
        }
        {
          name = "${key}__MODEL";
          value = "gpt-6.1-terra";
        }
      ])
      modelKeys)
    // cfg.environment
  ));
  container = {
    image = honchoImage;
    workdir = "/app";
    volumes = [
      "${postgresqlSocket}:${postgresqlSocket}:ro"
      "${tiktokenO200kBase}:/etc/honcho/tiktoken-cache/fb374d419588a4632f3f557e76b4b70aebbca790:ro"
      "${tiktokenCl100kBase}:/etc/honcho/tiktoken-cache/9b5ad71b2ce5302211f9c61530b329a4922fc6a4:ro"
    ];
    environment.TIKTOKEN_CACHE_DIR = "/etc/honcho/tiktoken-cache";
    environmentFiles = [publicEnvironment runtimeEnvironmentFile];
    extraOptions = ["--network=host"];
  };
in {
  options.services.honcho = {
    enable = lib.mkEnableOption "Honcho memory service";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/plastic-labs/honcho:v3.0.12@sha256:1e9dbc40136d3f9213ce7482b0eecac914b630ee3e714ea961bd763945f94be5";
      description = "Pinned Honcho API and deriver image.";
    };
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };
    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8000;
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Public Honcho environment overrides. Credentials come from apiKeyFile and the persisted JWT secret.";
    };
    apiKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime file containing the model gateway API key.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/honcho";
      description = "Directory containing the persisted JWT secret.";
    };
    restartTriggers = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
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

    systemd.services = {
      postgresql-setup.postStart = ''
        psql \
          --dbname=honcho \
          --set=ON_ERROR_STOP=1 \
          --command='CREATE EXTENSION IF NOT EXISTS vector'
      '';

      honcho-runtime-env = {
        description = "Prepare Honcho credentials";
        restartTriggers = cfg.restartTriggers;
        path = [pkgs.coreutils pkgs.openssl];
        unitConfig.RequiresMountsFor = cfg.stateDirectory;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = "honcho";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
        };
        script = ''
          set -euo pipefail
          mkdir -p ${lib.escapeShellArg cfg.stateDirectory}
          jwt_secret_file=${lib.escapeShellArg "${cfg.stateDirectory}/jwt-secret"}
          if [[ ! -s "$jwt_secret_file" ]]; then
            openssl rand -hex 32 > "$jwt_secret_file"
          fi
          api_token="$(tr -d '\r\n' < ${lib.escapeShellArg cfg.apiKeyFile})"
          if [[ -z "$api_token" ]]; then
            echo "Honcho model gateway token is empty" >&2
            exit 1
          fi
          printf 'AUTH_JWT_SECRET=%s\nLLM_OPENAI_API_KEY=%s\n' \
            "$(tr -d '\r\n' < "$jwt_secret_file")" "$api_token" > ${runtimeEnvironmentFile}.tmp
          mv ${runtimeEnvironmentFile}.tmp ${runtimeEnvironmentFile}
        '';
      };

      honcho-database-init = {
        description = "Initialize the Honcho database";
        after = [
          "postgresql-setup.service"
          "honcho-runtime-env.service"
        ];
        requires = [
          "postgresql-setup.service"
          "honcho-runtime-env.service"
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
            --env-file=${publicEnvironment} --env-file=${runtimeEnvironmentFile} \
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
            --env-file=${publicEnvironment} --env-file=${runtimeEnvironmentFile} \
            --volume=${postgresqlSocket}:${postgresqlSocket}:ro \
            --entrypoint=/app/.venv/bin/python \
            ${lib.escapeShellArg honchoImage} scripts/configure_embeddings.py --yes
        '';
      };

      podman-honcho-api = {
        after = [
          "honcho-database-init.service"
        ];
        requires = [
          "honcho-database-init.service"
        ];
        restartTriggers = cfg.restartTriggers;
      };

      podman-honcho-deriver = {
        restartTriggers = cfg.restartTriggers;
      };
    };

    virtualisation.oci-containers.containers = {
      honcho-api =
        container
        // {
          entrypoint = "/app/.venv/bin/fastapi";
          cmd = ["run" "--host" listenAddress "--port" (toString cfg.apiPort) "src/main.py"];
          volumes = container.volumes ++ ["${healthCheck}:/etc/honcho/healthcheck.py:ro"];
          extraOptions =
            container.extraOptions
            ++ [
              "--health-cmd=${healthCommand}"
              "--health-interval=1m"
              "--health-timeout=3s"
              "--health-retries=3"
              "--health-startup-cmd=${healthCommand}"
              "--health-startup-interval=2s"
              "--health-startup-timeout=3s"
              "--health-startup-retries=60"
            ];
          podman.sdnotify = "healthy";
        };
      honcho-deriver =
        container
        // {
          entrypoint = "/app/.venv/bin/python";
          cmd = ["-m" "src.deriver"];
          dependsOn = ["honcho-api"];
        };
    };
  };
}
