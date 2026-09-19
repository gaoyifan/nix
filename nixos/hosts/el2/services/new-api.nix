{
  config,
  lib,
  ...
}: let
  dataDirectory = "/pool1/services/new-api";
  hasSecrets = config.services.secrets.hasRealFiles;
in {
  age.secrets.new-api-env = lib.mkIf hasSecrets {
    file = config.services.secrets.filesDir + "/nixos/el2/new-api-env.age";
  };

  services.tailscale.serve.services.one-api.endpoints."tcp:80" = "http://127.0.0.1:9000";

  virtualisation.oci-containers.containers.new-api = {
    autoStart = false;
    image = "docker.io/calciumion/new-api@sha256:0a4d62b1b2b796a43a5e0ef92d49f12e0f229ab206b8f5a3a4cd42990121bfe1";
    environment.TZ = "Asia/Shanghai";
    environmentFiles = ["/run/agenix/new-api-env"];
    ports = ["127.0.0.1:9000:3000"];
    volumes = [
      "${dataDirectory}:/data"
      "${dataDirectory}/logs:/app/logs"
    ];
    cmd = [
      "--log-dir"
      "/app/logs"
    ];
  };

  systemd.services.podman-new-api = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
    restartTriggers = lib.optional hasSecrets config.age.secrets.new-api-env.file;
    unitConfig.ConditionPathExists = "${dataDirectory}/one-api.db";
  };
}
