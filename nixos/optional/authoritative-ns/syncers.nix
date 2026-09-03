{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.authoritativeNs;
  hasSecrets = config.services.secrets.hasRealFiles;
  pythonPackages = [
    pkgs.python3Packages.httpx
    pkgs.python3Packages.pyyaml
  ];
  python = pkgs.python3.withPackages (_: pythonPackages);
  tailscaleSyncer = pkgs.writers.writePython3Bin "powerdns-tailscale-syncer" {
    libraries = [pkgs.python3Packages.httpx];
    flakeIgnore = ["E501"];
  } (builtins.readFile ./tailscale-syncer.py);
  viewSyncer = pkgs.writers.writePython3Bin "powerdns-view-syncer" {
    libraries = pythonPackages;
    flakeIgnore = ["E501"];
  } (builtins.readFile ./view-syncer.py);
  syncersTest =
    pkgs.runCommand "powerdns-syncers-check" {
      nativeBuildInputs = [python];
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    } ''
      python ${./test_syncers.py} \
        ${./tailscale-syncer.py} \
        ${./view-syncer.py}
      touch $out
    '';
  syncerService = description: executable: requiredUnits: {
    inherit description;
    wantedBy = cfg.wantedBy;
    requires = ["pdns.service"] ++ requiredUnits;
    after = ["pdns.service"] ++ requiredUnits;
    restartTriggers = lib.optional hasSecrets config.age.secrets.nylon-powerdns-api-key.file;
    serviceConfig = {
      DynamicUser = true;
      EnvironmentFile = config.age.templates."powerdns.env".path;
      ExecStart = lib.getExe executable;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  tailscaleSyncerServices = lib.mapAttrs' (name: instance:
    lib.nameValuePair "powerdns-tailscale-syncer-${name}" (
      (syncerService "Synchronize ${instance.zone} from Tailscale" tailscaleSyncer [instance.sourceUnit])
      // {
        environment = {
          PDNS_API_URL = "http://127.0.0.1:8081/api/v1";
          SYNC_INTERVAL = "60";
          TS_BASE_DOMAIN = instance.zone;
          TS_SOCKET = instance.socketPath;
        };
      }
    ))
  cfg.tailscaleSyncers;
  viewsConfig = (pkgs.formats.yaml {}).generate "powerdns-views.yaml" {
    managed_only = true;
    views =
      lib.genAttrs [
        "cernet"
        "chinanet"
        "cmcc"
        "unicom"
      ] (name: {
        priority = 10;
        url = "https://gaoyifan.github.io/china-operator-ip/${name}46.txt";
      })
      // {
        china = {
          priority = 5;
          url = "https://gaoyifan.github.io/china-operator-ip/china46.txt";
        };
      };
  };
in {
  options.services.authoritativeNs.tailscaleSyncers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        zone = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "PowerDNS zone populated by this Tailscale syncer.";
        };

        socketPath = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Path to the tailscaled LocalAPI Unix socket.";
        };

        sourceUnit = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Unit that provides the tailscaled LocalAPI socket.";
        };
      };
    });
    default = {};
    description = "Named Tailscale-to-PowerDNS synchronizer instances.";
  };

  config = lib.mkIf (cfg.role == "primary") {
    system.build.powerdnsSyncersTest = syncersTest;

    systemd.services =
      {
        powerdns-view-syncer =
          (syncerService "Synchronize PowerDNS views" viewSyncer [])
          // {
            environment = {
              PDNS_API_URL = "http://127.0.0.1:8081/api/v1";
              SYNC_CONFIG_PATH = viewsConfig;
              SYNC_INTERVAL = "86400";
            };
          };
      }
      // tailscaleSyncerServices;
  };
}
