{config, ...}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [
    ../../optional/acme-certificates.nix
  ];

  services.openssh.settings.MaxStartups = 100;

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
