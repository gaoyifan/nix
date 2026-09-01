{
  config,
  inputs,
  lib,
  pkgs,
  username,
  ...
}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [
    inputs.codex-capacity-proxy.nixosModules.default
    ../../optional/acme-certificates.nix
  ];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    acme-repository-pull-key.file = config.services.secrets.filesDir + "/nixos/acme-repository-pull-key.age";
  };

  services = {
    codex-capacity-proxy.enable = true;
    acmeCertificates = {
      enable = true;
      restartServices = ["tailscale-serve"];
    };
    tailscale.serve = {
      enable = true;
      configFile = pkgs.writeText "oracle2-tailscale-serve.json" (builtins.toJSON {
        version = "0.0.1";
        services = {
          "svc:bitmagnet".endpoints."tcp:80" = "http://127.0.0.1:3333";
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

  systemd.services.bitmagnet-oracle2 = {
    description = "Bitmagnet Compose project";
    wants = ["docker.service" "network-online.target"];
    after = ["docker.service" "network-online.target"];
    wantedBy = ["multi-user.target"];
    environment.DOCKER_BUILDKIT = "1";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "${config.users.users.${username}.home}/docker-run-scripts/bitmagnet-oracle2";
      ExecStart = "${pkgs.docker}/bin/docker compose up -d --build";
      ExecStop = "${pkgs.docker}/bin/docker compose stop";
    };
  };
}
