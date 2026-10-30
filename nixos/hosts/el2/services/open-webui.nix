{
  config,
  lib,
  ...
}: let
  dataDirectory = "/pool1/services/open-webui";
  hasSecrets = config.services.secrets.hasRealFiles;
in {
  age.secrets.open-webui-env = lib.mkIf hasSecrets {
    file = config.services.secrets.filesDir + "/nixos/el2/open-webui-env.age";
  };

  services.tailscale.serve.services.open-webui.endpoints."tcp:80" = "http://127.0.0.1:3002";

  virtualisation.oci-containers.containers.open-webui = {
    autoStart = false;
    image = "ghcr.io/open-webui/open-webui@sha256:0b399a8ba34558e181d316750455f2a95376a38cd60a61b9c942e138898944bd";
    environmentFiles = ["/run/agenix/open-webui-env"];
    ports = ["127.0.0.1:3002:8080"];
    volumes = ["${dataDirectory}:/app/backend/data"];
  };

  systemd.services.podman-open-webui = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
    restartTriggers = lib.optional hasSecrets config.age.secrets.open-webui-env.file;
    unitConfig.ConditionPathExists = "${dataDirectory}/webui.db";
  };
}
