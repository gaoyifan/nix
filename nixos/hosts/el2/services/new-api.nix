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
    image = "docker.io/calciumion/new-api@sha256:80d2be398567c4d59235d74bd7c21417ebfd612cd3452863ba8bd8dcad4fc437";
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
