{
  host = {
    config,
    pkgs,
    lib,
    ...
  }: let
    publicEnv = pkgs.writeText "rakazo-env-public" ''
      BETTER_AUTH_URL=https://rakazo.ts.gaof.net
      WEB_ORIGIN=https://rakazo.ts.gaof.net
      API_URL=https://rakazo.ts.gaof.net
      RAKAZO_HOST=rakazo.ts.gaof.net
      RAKAZO_WEB_BIND_IP=100.64.2.81
      RAKAZO_IMAGE_TAG=v0.1.6
      RAKAZO_COMPUTER_IMAGE_TAG=v0.1.6
    '';
  in {
    config = lib.mkIf config.microvm.host.enable {
      systemd.services = {
        rakazo-prepare = {
          description = "Prepare Rakazo disk directory and runtime credentials";
          requires = ["zfs-unlock-mount.service"];
          after = ["zfs-unlock-mount.service"];
          restartTriggers = lib.optional config.services.secrets.hasRealFiles config.age.secrets.rakazo-env.file;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
          };
          script = ''
            install -d -m 0700 -o microvm -g kvm /pool1/services/rakazo
            install -d -m 0700 -o root -g root /run/rakazo
            cat ${publicEnv} /run/agenix/rakazo-env > /run/rakazo/env.tmp
            chmod 0400 /run/rakazo/env.tmp
            mv /run/rakazo/env.tmp /run/rakazo/env
          '';
        };
        install-microvm-rakazo = {
          requires = ["rakazo-prepare.service"];
          after = ["rakazo-prepare.service"];
        };
        "microvm@rakazo" = {
          wantedBy = ["el2-services.target"];
          requires = ["install-microvm-rakazo.service"];
          restartTriggers = [publicEnv] ++ lib.optional config.services.secrets.hasRealFiles config.age.secrets.rakazo-env.file;
        };
        "microvm-virtiofsd@rakazo" = {
          requires = ["rakazo-prepare.service"];
          after = ["rakazo-prepare.service"];
        };
      };
    };
  };

  guest = rakazoSource: {
    lib,
    pkgs,
    ...
  }: let
    # Keep the release's Compose topology; only the web listener needs to be
    # reachable from el2's Tailscale proxy instead of guest loopback.
    composeFile = pkgs.writeText "rakazo-compose.yml" (lib.replaceStrings
      ["127.0.0.1:\${RAKAZO_WEB_PORT:-5173}:5173"]
      ["\${RAKAZO_WEB_BIND_IP:-127.0.0.1}:\${RAKAZO_WEB_PORT:-5173}:5173"]
      (builtins.readFile "${rakazoSource}/infra/compose/docker-compose.images.yml"));
    compose = "${pkgs.docker-compose}/bin/docker-compose --project-directory /run/rakazo -f /run/rakazo/compose.yml -f ${composeOverrides}";
    composeOverrides = (pkgs.formats.json {}).generate "rakazo-compose-overrides.json" {
      # The supervisor attaches these containers to computer networks at runtime.
      # Preserve their default gateway so the first desktop request keeps its
      # connection to the host's web proxy while that network is attached.
      services = lib.genAttrs ["web" "supervisor"] (_: {networks.app.gw_priority = 1;});
      volumes = lib.genAttrs ["appdata" "pgdata"] (name: {
        driver = "local";
        driver_opts = {
          type = "none";
          o = "bind";
          device = "/var/lib/rakazo/${name}";
        };
      });
    };
  in {
    networking.firewall.allowedTCPPorts = [5173];

    virtualisation.docker.enable = true;
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
      hostKeys = [
        {
          path = "/var/lib/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    };
    systemd.tmpfiles.rules = [
      "d /var/lib/rakazo 0700 root root -"
      "d /var/lib/rakazo/appdata 0750 1000 1000 -"
      "d /var/lib/rakazo/pgdata 0700 root root -"
      "d /var/lib/rakazo/backups 0700 root root -"
    ];
    systemd.services.rakazo = {
      description = "Rakazo application and local Docker computers";
      wantedBy = ["multi-user.target"];
      requires = ["docker.service"];
      after = ["docker.service"];
      serviceConfig = {
        # First image pulls and migrations must not hold up VM boot readiness.
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        UMask = "0077";
        ExecStop = "${compose} stop";
      };
      preStart = ''
        install -d -m 0700 /run/rakazo
        ln -sfn /etc/rakazo-secrets/env /run/rakazo/.env
        ln -sfn ${composeFile} /run/rakazo/compose.yml
      '';
      script = ''
        ${compose} up -d --wait
      '';
    };

    # The encrypted var.img is covered by el2's existing ZFS replication of
    # pool1/services. Keep a logical database dump in addition to disk snapshots.
    systemd.services.rakazo-database-backup = {
      description = "Dump the Rakazo PostgreSQL database";
      requires = ["rakazo.service"];
      after = ["rakazo.service"];
      startAt = "*-*-* 02:00:00";
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        ${compose} exec -T postgres pg_dump -U rakazo -Fc rakazo > /var/lib/rakazo/backups/database.dump.tmp
        mv /var/lib/rakazo/backups/database.dump.tmp /var/lib/rakazo/backups/database.dump
      '';
    };
    systemd.timers.rakazo-database-backup.timerConfig.Persistent = true;
    system.stateVersion = "26.05";
  };
}
