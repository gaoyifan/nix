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

  services.resolved.settings.Resolve = {
    DNS = [config.networking.homeRouter.serviceAddresses.ipv4];
    Domains = ["~."];
  };
  services.resolved.dnsDelegates = {
    cjia.Delegate = {
      DNS = ["100.65.1.254"];
      Domains = ["cjia.gaof.net"];
    };
    somo.Delegate = {
      DNS = ["100.65.2.254"];
      Domains = ["somo.gaof.net"];
    };
    wgIplcEndpoint.Delegate = {
      DNS = [
        "223.5.5.5"
        "223.6.6.6"
      ];
      Domains = ["int.automesh.org"];
    };
  };
}
