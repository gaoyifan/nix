{
  config,
  lib,
  ...
}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [
    ../../optional/acme-certificates.nix
    ../../optional/diverge.nix
  ];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    acme-repository-pull-key.file = config.services.secrets.filesDir + "/nixos/acme-repository-pull-key.age";
  };

  services.openssh.settings.MaxStartups = 100;
  services.fail2ban.enable = true;
  services.diverge.enable = true;

  services.acmeCertificates = {
    enable = true;
    restartServices = ["podman-light-single"];
  };

  virtualisation.oci-containers.containers.light-single = {
    image = "docker.io/gaoyifan/light-server:single";
    volumes = ["${certDir}:/usr/local/openresty/nginx/conf/ssl:ro"];
    extraOptions = ["--network=host"];
  };
}
