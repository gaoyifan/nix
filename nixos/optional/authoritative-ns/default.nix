{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.authoritativeNs;
  primary = cfg.role == "primary";
  defaultDataDirectory = "/var/lib/powerdns";
  hasSecrets = config.services.secrets.hasRealFiles;
  zoneRepository = "${cfg.dataDirectory}-zones";
  lightningstreamConfig = (pkgs.formats.yaml {}).generate "lightningstream.yaml" {
    instance = config.networking.hostName;
    storage_poll_interval = "8s";
    lmdbs = {
      main = {
        path = "${cfg.dataDirectory}/pdns.lmdb";
        schema_tracks_changes = true;
        options = {
          no_subdir = true;
          create = true;
        };
      };
      shard = {
        path = "${cfg.dataDirectory}/pdns.lmdb-0";
        schema_tracks_changes = true;
        options = {
          no_subdir = true;
          create = true;
        };
      };
    };
    sweeper = {
      enabled = true;
      retention_days = 30;
      first_interval = "1m";
    };
    storage = {
      type = "s3";
      options = {
        access_key = "\${S3_ACCESS_KEY}";
        secret_key = "\${S3_SECRET_KEY}";
        region = "\${S3_REGION}";
        bucket = "\${S3_BUCKET}";
        endpoint_url = "\${S3_ENDPOINT}";
        use_update_marker = true;
      };
      cleanup = {
        enabled = true;
        interval = "24h";
      };
    };
  };
  wgHealthcheckConfig = (pkgs.formats.yaml {}).generate "powerdns-wg-healthcheck.yaml" {
    listen = "0.0.0.0:8088";
    servers_dir = "/run/credentials/powerdns-wg-healthcheck.service";
    check_target = "1.1.1.1";
    check_interval = "5s";
    loss_window = "5m";
    max_packet_loss = 0.1;
    ping_timeout = "2s";
    primary = "primary";
    backup = "backup";
  };
in {
  imports = [
    ./syncers.nix
    ./zone-backup.nix
  ];

  options.services.authoritativeNs = {
    role = lib.mkOption {
      type = lib.types.enum [
        "primary"
        "secondary"
      ];
      default = "secondary";
      description = "Whether this node manages authoritative DNS state or only serves synchronized state.";
    };

    dataDirectory = lib.mkOption {
      type = lib.types.str;
      default = defaultDataDirectory;
      description = "Persistent PowerDNS LMDB directory.";
    };

    wantedBy = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["multi-user.target"];
      description = "Targets that start the authoritative DNS role.";
    };

    requiredUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Units that must start before persistent primary state is prepared.";
    };
  };

  config = {
    age.templates."powerdns.env" = lib.mkIf primary {
      content = ''
        PDNS_API_KEY=${config.age.placeholder.nylon-powerdns-api-key or ""}
      '';
    };

    age.secrets = lib.mkIf hasSecrets (lib.mkMerge [
      {
        lightningstream-env.file = config.services.secrets.filesDir + "/nixos/lightningstream-env.age";
      }
      (lib.mkIf primary {
        powerdns-wg-backup-conf.file = config.services.secrets.filesDir + "/nixos/${config.networking.hostName}/powerdns-wg-backup.conf.age";
        powerdns-wg-primary-conf.file = config.services.secrets.filesDir + "/nixos/${config.networking.hostName}/powerdns-wg-primary.conf.age";
      })
    ]);

    services = lib.mkMerge [
      {
        powerdns = {
          enable = true;
          secretFile = lib.mkIf primary config.age.templates."powerdns.env".path;
          extraConfig = ''
            launch=lmdb
            lmdb-filename=${cfg.dataDirectory}/pdns.lmdb
            lmdb-shards=1
            lmdb-lightning-stream=yes
            views=yes
            edns-subnet-processing=yes
            zone-cache-refresh-interval=1
            zone-metadata-cache-ttl=0
            dname-processing=yes
            expand-alias=yes
            resolver=${
              if primary
              then "127.0.0.53:53"
              else "[::1]:53"
            }
            security-poll-suffix=
            enable-lua-records=yes
            ${lib.optionalString primary ''
              local-address=0.0.0.0,::
              local-port=5354
              api=yes
              api-key=''${PDNS_API_KEY}
              webserver=yes
              webserver-address=127.0.0.1
              webserver-allow-from=127.0.0.1,::1
              webserver-port=8081
              webserver-password=''${PDNS_API_KEY}
            ''}
          '';
        };
        resolved = {
          enable = lib.mkForce true;
          settings.Resolve.DNSStubListener = lib.mkIf (!primary) false;
        };
      }
      (lib.mkIf primary {
        caddy = {
          enable = true;
          virtualHosts."http://:8082".extraConfig = ''
            bind 127.0.0.1
            root * ${pkgs.powerdns-ui}
            handle /api/v1/* {
              reverse_proxy 127.0.0.1:8081
            }
            handle {
              try_files {path} /index.html
              file_server
            }
          '';
        };
        tailscale.serve.services.pdns-ui.endpoints."tcp:80" = "http://127.0.0.1:8082";
      })
    ];

    environment.etc =
      {
        "lightningstream.yaml".source = lightningstreamConfig;
      }
      // lib.optionalAttrs (!primary) {
        "resolv.conf".source = lib.mkForce "/run/systemd/resolve/resolv.conf";
      };

    systemd.tmpfiles.rules = lib.optionals primary ["d /etc/caddy 0755 root root -"];

    systemd = {
      services = lib.mkMerge [
        {
          pdns = {
            wantedBy = lib.mkForce cfg.wantedBy;
            requires = lib.optionals primary ["powerdns-state.service"];
            after = lib.optionals primary ["powerdns-state.service"];
            restartTriggers = lib.optional (primary && hasSecrets) config.age.secrets.nylon-powerdns-api-key.file;
            unitConfig = lib.optionalAttrs primary {
              ConditionPathExists = [
                "${cfg.dataDirectory}/pdns.lmdb"
                "${cfg.dataDirectory}/pdns.lmdb-0"
              ];
            };
            serviceConfig.StateDirectory = lib.mkIf (cfg.dataDirectory == defaultDataDirectory) "powerdns";
          };

          lightningstream = {
            description = "Synchronize PowerDNS LMDB databases through S3";
            wantedBy = cfg.wantedBy;
            requires = ["pdns.service"] ++ lib.optionals primary ["powerdns-state.service"];
            after = ["pdns.service"] ++ lib.optionals primary ["powerdns-state.service"];
            serviceConfig = {
              User = "pdns";
              Group = "pdns";
              EnvironmentFile = "/run/agenix/lightningstream-env";
              ExecStart = "${lib.getExe pkgs.lightningstream} --config /etc/lightningstream.yaml sync";
              Restart = "on-failure";
              RestartSec = 1;
            };
          };
        }
        (lib.mkIf primary {
          powerdns-state = {
            description = "Prepare PowerDNS primary state";
            requires = cfg.requiredUnits;
            after = cfg.requiredUnits;
            before = [
              "pdns.service"
              "lightningstream.service"
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "powerdns-state" ''
                ${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o pdns -g pdns ${cfg.dataDirectory} ${zoneRepository}
                ${lib.getExe' pkgs.coreutils "chown"} -R pdns:pdns ${cfg.dataDirectory} ${zoneRepository}
              '';
            };
          };

          powerdns-wg-healthcheck = {
            description = "Check WireGuard-backed authoritative DNS endpoints";
            wantedBy = cfg.wantedBy;
            serviceConfig = {
              DynamicUser = true;
              ExecStart = "${lib.getExe pkgs.ns-wg-healthcheck} --config ${wgHealthcheckConfig}";
              LoadCredential = [
                "backup.conf:/run/agenix/powerdns-wg-backup-conf"
                "primary.conf:/run/agenix/powerdns-wg-primary-conf"
              ];
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectHome = true;
              ProtectSystem = "strict";
              Restart = "on-failure";
              RestartSec = 5;
            };
          };

          caddy = {
            wantedBy = lib.mkForce cfg.wantedBy;
            after = ["pdns.service"];
          };
        })
      ];
    };
  };
}
