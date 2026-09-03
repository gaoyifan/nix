{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.tailscale.serve;
  certificateType = lib.types.submodule {
    options = {
      certFile = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "Absolute path to the PEM-encoded TLS certificate.";
      };
      keyFile = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "Absolute path to the PEM-encoded TLS private key.";
      };
    };
  };
  serviceConfig =
    lib.mapAttrs' (
      name: service:
        lib.nameValuePair "svc:${name}" (
          {
            endpoints =
              service.endpoints
              // lib.mapAttrs (_: target: {
                inherit target;
                tls = true;
              })
              service.tlsEndpoints;
          }
          // lib.optionalAttrs (service.certificate != null) {inherit (service) certificate;}
          // lib.optionalAttrs (service.advertised != null) {inherit (service) advertised;}
        )
    )
    cfg.services;
  usesExtendedConfig = lib.any (
    service: service.certificate != null || service.tlsEndpoints != {}
  ) (lib.attrValues cfg.services);
in {
  options.services.tailscale.serve.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        certificate = lib.mkOption {
          type = lib.types.nullOr certificateType;
          default = null;
          description = "Certificate managed outside Tailscale for this service's TLS endpoints.";
        };
        tlsEndpoints = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Incoming TCP port ranges on which Tailscale terminates TLS, mapped to local targets.";
        };
      };
    });
  };

  config = lib.mkIf usesExtendedConfig {
    assertions = [
      {
        assertion = lib.all (
          service: builtins.intersectAttrs service.endpoints service.tlsEndpoints == {}
        ) (lib.attrValues cfg.services);
        message = "services.tailscale.serve.services.*.endpoints and tlsEndpoints must not share keys";
      }
    ];

    services.tailscale.serve.configFile = (pkgs.formats.json {}).generate "tailscale-serve-config.json" {
      version = "0.0.1";
      services = serviceConfig;
    };
  };
}
