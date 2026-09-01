{config, ...}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  networking.edgeFirewall.extraPublicTcpPorts = ["29979-29980"];

  virtualisation.oci-containers.containers.light-single = {
    image = "docker.io/gaoyifan/light-server:single";
    volumes = ["${certDir}:/usr/local/openresty/nginx/conf/ssl:ro"];
    extraOptions = ["--network=host"];
  };
}
