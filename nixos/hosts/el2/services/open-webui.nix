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
    image = "ghcr.io/open-webui/open-webui@sha256:1a6399d237dc392a2313e0ca826020b3fd5d22536357840eb63393d18dc8b924";
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
