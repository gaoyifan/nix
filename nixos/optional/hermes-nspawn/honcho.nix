{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-nspawn;
  listenAddress = config.networking.homeRouter.serviceAddresses.ipv4;
in {
  imports = [
    ../honcho.nix
    (lib.mkAliasOptionModule ["services" "hermes-nspawn" "honcho" "apiPort"] ["services" "honcho" "apiPort"])
  ];

  config = lib.mkIf cfg.enable {
    services.honcho = {
      enable = true;
      inherit listenAddress;
      apiKeyFile = "${cfg.newApiTokenDirectory}/honcho";
      restartTriggers = lib.optional (cfg.newApiTokenRestartTriggers ? honcho) cfg.newApiTokenRestartTriggers.honcho;
      environment = {
        CACHE_ENABLED = "true";
        CACHE_URL = "redis://127.0.0.1:6379/0?suppress=true";
        LLM_OPENAI_BASE_URL = "http://${listenAddress}:3002/v1";
        EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL = "http://127.0.0.1:3000/v1";
      };
    };
    services.postgresql.package = pkgs.postgresql_15;
    services.redis.servers.honcho = {
      enable = true;
      port = 6379;
    };
    systemd.services.honcho-runtime-env.serviceConfig = {
      StateDirectory = "honcho";
      StateDirectoryMode = "0700";
    };
    systemd.services.podman-honcho-api = {
      after = ["redis-honcho.service"];
      requires = ["redis-honcho.service"];
    };
  };
}
