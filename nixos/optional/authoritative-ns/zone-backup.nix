{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.authoritativeNs;
  zoneRepository = "${cfg.dataDirectory}-zones";
  zoneBackup = pkgs.writeShellApplication {
    name = "powerdns-zone-backup";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
      pkgs.pdns
    ];
    text = ''
      repo=${lib.escapeShellArg zoneRepository}
      backup="$repo/backup"
      git -C "$repo" config user.name 'Backup Bot'
      git -C "$repo" config user.email ns@gaof.net
      branch="$(git -C "$repo" branch --show-current)"
      test -n "$branch"

      tmp="$(mktemp -d "$repo/.backup.XXXXXX")"
      trap 'rm -rf "$tmp"; git -C "$repo" rebase --abort >/dev/null 2>&1 || true' EXIT

      mapfile -t zones < <(pdnsutil --config-dir=/etc/pdns zone list-all | sed '/^All zonecount:/d; /^$/d')
      ((''${#zones[@]} > 0))
      for zone in "''${zones[@]}"; do
        [[ "$zone" =~ ^[A-Za-z0-9._-]+$ ]]
        pdnsutil --config-dir=/etc/pdns zone list "$zone" >"$tmp/$zone.db"
      done

      mkdir -p "$backup"
      find "$backup" -maxdepth 1 -type f -name '*.db' -delete
      mv "$tmp"/*.db "$backup"/

      git -C "$repo" add -A backup
      if ! git -C "$repo" diff --cached --quiet; then
        git -C "$repo" commit -m "auto: backup zones $(date '+%Y-%m-%d %H:%M:%S')"
      fi
      export GIT_SSH_COMMAND="ssh -i $CREDENTIALS_DIRECTORY/git-key -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"
      git -C "$repo" pull --rebase origin "$branch"
      git -C "$repo" push origin "$branch"
    '';
  };
in {
  config = lib.mkIf (cfg.role == "primary") {
    age.secrets.powerdns-backup-ssh-key = lib.mkIf config.services.secrets.hasRealFiles {
      file = config.services.secrets.filesDir + "/nixos/${config.networking.hostName}/powerdns-backup-ssh-key.age";
    };

    systemd = {
      services.powerdns-zone-backup = {
        description = "Export PowerDNS zones to Git";
        requires = [
          "pdns.service"
          "powerdns-state.service"
        ];
        after = [
          "pdns.service"
          "powerdns-state.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "pdns";
          Group = "pdns";
          ExecStart = lib.getExe zoneBackup;
          LoadCredential = "git-key:/run/agenix/powerdns-backup-ssh-key";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            cfg.dataDirectory
            zoneRepository
          ];
        };
      };

      timers.powerdns-zone-backup = {
        wantedBy = cfg.wantedBy;
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
        };
      };
    };
  };
}
