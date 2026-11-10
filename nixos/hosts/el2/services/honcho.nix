{
  config,
  lib,
  ...
}: {
  imports = [../../../optional/honcho.nix];

  age.secrets.honcho-api-token = lib.mkIf config.services.secrets.hasRealFiles {
    file = config.services.secrets.filesDir + "/nixos/el2/honcho-api-token.age";
    group = "codex-api";
    mode = "0440";
  };

  services.honcho = {
    enable = true;
    image = "ghcr.io/plastic-labs/honcho:v3.2.2@sha256:1373afb45113e861515b2c01d3db787391cc6e7f3e3e6721c45d863153b5e5b4";
    listenAddress = "100.64.2.254";
    apiPort = 8003;
    stateDirectory = "/pool1/services/honcho";
    apiKeyFile = "/run/agenix/honcho-api-token";
    restartTriggers = lib.optional config.services.secrets.hasRealFiles config.age.secrets.honcho-api-token.file;
    environment = {
      VECTOR_STORE_TYPE = "pgvector";
      LLM_OPENAI_BASE_URL = "http://127.0.0.1:3003/v1";
      EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL = "http://127.0.0.1:9000/v1";
    };
  };

  virtualisation.oci-containers.containers = {
    honcho-api.autoStart = false;
    honcho-deriver.autoStart = false;
  };
  systemd.services.podman-honcho-api = {
    wantedBy = ["el2-services.target"];
    requires = ["codex-api.service" "podman-new-api.service"];
    after = ["codex-api.service" "podman-new-api.service"];
  };
  systemd.services.podman-honcho-deriver.wantedBy = ["el2-services.target"];

  services.postgresqlBackup = {
    enable = true;
    databases = ["honcho"];
    location = "/pool1/services/honcho/backups";
    compression = "zstd";
  };

  systemd.services.honcho-runtime-env = {
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
    preStart = ''
      install -d -m 0750 -g postgres /pool1/services/honcho
    '';
  };
}
