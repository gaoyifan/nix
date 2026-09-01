{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [
    inputs.codex-capacity-proxy.nixosModules.default
    ../../optional/acme-certificates.nix
    ../../optional/bitmagnet.nix
  ];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    acme-repository-pull-key.file = config.services.secrets.filesDir + "/nixos/acme-repository-pull-key.age";
  };

  services = {
    codex-capacity-proxy.enable = true;
    postgresql.dataDir = "/srv/docker/bitmagnet-postgres";
    acmeCertificates = {
      enable = true;
      restartServices = ["tailscale-serve"];
    };
    tailscale.serve = {
      enable = true;
      configFile = pkgs.writeText "oracle2-tailscale-serve.json" (builtins.toJSON {
        version = "0.0.1";
        services = {
          "svc:bitmagnet".endpoints."tcp:80" = "http://${config.services.bitmagnet.settings.http_server.port}";
          "svc:codex-capacity-proxy" = {
            certificate = {
              certFile = "${certDir}/fullchain.pem";
              keyFile = "${certDir}/privkey.pem";
            };
            endpoints = {
              "tcp:443" = {
                target = "http://127.0.0.1:${toString config.services.codex-capacity-proxy.port}";
                tls = true;
              };
            };
          };
        };
      });
    };
  };
}
