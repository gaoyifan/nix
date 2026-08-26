{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
  serviceName = "svc:codex-capacity-proxy";
  serveConfig = pkgs.writeText "codex-capacity-proxy-tailscale-serve.json" (builtins.toJSON {
    version = "0.0.1";
    services = {
      "${serviceName}" = {
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
      configFile = serveConfig;
    };
  };
}
