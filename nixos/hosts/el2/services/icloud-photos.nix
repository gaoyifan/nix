{
  config,
  lib,
  pkgs,
  ...
}: let
  stateDirectory = "/var/lib/icloud-photos-backup";
  metricsDirectory = "/var/lib/prometheus-node-exporter-text-files";
  grafanaDashboard = import ../../../optional/grafana-dashboard.nix;
  backup = pkgs.writeShellApplication {
    name = "icloud-photos-backup";
    runtimeInputs = with pkgs; [coreutils jq openssh rsync util-linux];
    text = ''
      destination=/pool0/footage2
      started_at=$(date +%s)
      missing=NaN
      errors=NaN
      apfs_used_ratio=NaN

      publish_metrics() {
        local exit_status=$? last_success=0
        if [[ -f ${stateDirectory}/last-success ]]; then
          last_success=$(cat ${stateDirectory}/last-success)
        fi
        cat > ${metricsDirectory}/icloud-photos.prom.tmp <<METRICS
      icloud_photos_backup_last_success_timestamp_seconds $last_success
      icloud_photos_backup_last_attempt_timestamp_seconds $started_at
      icloud_photos_backup_failed $((exit_status != 0))
      icloud_photos_export_missing $missing
      icloud_photos_export_errors $errors
      icloud_photos_apfs_used_ratio $apfs_used_ratio
      METRICS
        chmod 644 ${metricsDirectory}/icloud-photos.prom.tmp
        mv ${metricsDirectory}/icloud-photos.prom.tmp ${metricsDirectory}/icloud-photos.prom
      }
      trap publish_metrics EXIT

      # Never create archive files on the root filesystem while the dataset is locked.
      if [[ $(findmnt --noheadings --mountpoint "$destination" --output SOURCE) != pool0/footage2 ]]; then
        echo "pool0/footage2 is not mounted at $destination" >&2
        exit 1
      fi

      export_status=0
      ssh -F ${sshConfig} icloud-photos /Users/yifan/.local/bin/icloud-photos-export || export_status=$?

      # One pull per attempt, including partially successful exports. Cloud deletions
      # are intentionally never propagated to the archive.
      rsync -a --partial-dir=.rsync-partial --chmod=D700,F600 --chown=yifan:users \
        -e 'ssh -F ${sshConfig}' \
        icloud-photos:/Volumes/Photos/icloud-export/ "$destination/"

      status="$destination/.backup-status.json"
      if ! jq -e --argjson started_at "$started_at" '
        (.completed_at | type == "number") and .completed_at >= $started_at and
        (.missing | type == "number") and .missing >= 0 and
        (.errors | type == "number") and .errors >= 0 and
        (.apfs_used_ratio | type == "number") and
        .apfs_used_ratio >= 0 and .apfs_used_ratio <= 1 and
        (.complete | type == "boolean")
      ' "$status" >/dev/null; then
        echo "Missing, stale, or invalid guest export status" >&2
        exit 1
      fi
      missing=$(jq -r '.missing' "$status")
      errors=$(jq -r '.errors' "$status")
      apfs_used_ratio=$(jq -r '.apfs_used_ratio' "$status")
      if (( export_status != 0 )) || ! jq -e '.complete and .missing == 0 and .errors == 0' "$status" >/dev/null; then
        echo "Export incomplete: ssh=$export_status missing=$missing errors=$errors" >&2
        exit 1
      fi

      date +%s > ${stateDirectory}/last-success.tmp
      mv ${stateDirectory}/last-success.tmp ${stateDirectory}/last-success
      echo "iCloud Photos archive complete at $destination"
    '';
  };
  sshConfig = pkgs.writeText "icloud-photos-ssh-config" ''
    Host icloud-photos
      HostName 100.64.2.80
      User yifan
      IdentityFile /run/agenix/icloud-photos-ssh-key
      IdentitiesOnly yes
      BatchMode yes
      StrictHostKeyChecking no
      UserKnownHostsFile ${stateDirectory}/known_hosts
      ConnectTimeout 30
      ServerAliveInterval 30
      ServerAliveCountMax 3
  '';
in {
  age.secrets.icloud-photos-ssh-key = lib.mkIf config.services.secrets.hasRealFiles {
    file = config.services.secrets.filesDir + "/nixos/el2/icloud-photos-ssh-key.age";
  };

  systemd.tmpfiles.rules = ["d ${metricsDirectory} 0755 root root -"];
  systemd.services.icloud-photos-backup = {
    description = "Archive iCloud Photos from Hackintosh to pool0/footage2";
    after = ["network-online.target" "zfs-unlock-mount.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "icloud-photos-backup";
      StateDirectoryMode = "0700";
      UMask = "0077";
      TimeoutStartSec = "infinity";
      ExecStart = "${backup}/bin/icloud-photos-backup";
    };
  };

  services.prometheus = {
    exporters.node.extraFlags = ["--collector.textfile.directory=${metricsDirectory}"];
    scrapeConfigs = [
      {
        job_name = "icloud-photos";
        params."collect[]" = ["textfile"];
        static_configs = [{targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];}];
      }
    ];
    rules = [
      (builtins.toJSON {
        groups = [
          {
            name = "icloud-photos";
            rules = [
              {
                alert = "ICloudPhotosBackupStale";
                expr = "time() - icloud_photos_backup_last_success_timestamp_seconds{job=\"icloud-photos\"} > 43200 or absent(icloud_photos_backup_last_success_timestamp_seconds{job=\"icloud-photos\"})";
                labels.severity = "warning";
                annotations.summary = "No complete iCloud Photos backup in 12 hours";
              }
              {
                alert = "ICloudPhotosBackupFailed";
                expr = "icloud_photos_backup_failed{job=\"icloud-photos\"} > 0 or icloud_photos_export_missing{job=\"icloud-photos\"} > 0 or icloud_photos_export_errors{job=\"icloud-photos\"} > 0";
                labels.severity = "warning";
                annotations.summary = "iCloud Photos backup or export is incomplete";
              }
              {
                alert = "ICloudPhotosAPFSFull";
                expr = "icloud_photos_apfs_used_ratio{job=\"icloud-photos\"} > 0.85";
                labels.severity = "warning";
                annotations.summary = "Hackintosh Photos volume is more than 85% full";
              }
            ];
          }
        ];
      })
    ];
  };

  services.grafana.provision.dashboards.settings.providers = [
    {
      name = "icloud-photos";
      options.path = pkgs.writeTextDir "icloud-photos.json" (builtins.toJSON (grafanaDashboard.build {
        variables = [];
        source = {
          name = "icloud-photos";
          title = "iCloud Photos backup";
          tags = ["backup" "icloud"];
          timeFrom = "now-7d";
          panels =
            map (item: {
              inherit (item) id title;
              queries = [
                {
                  refId = "A";
                  query = {
                    inherit (item) expr;
                    instant = true;
                  };
                }
              ];
              visualization = {
                type = "stat";
                options = {
                  colorMode = "value";
                  graphMode = "none";
                };
                fieldDefaults = {
                  inherit (item) unit;
                  min = 0;
                  noValue = "Unknown";
                  color.mode = "thresholds";
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      {
                        color = "green";
                        value = null;
                      }
                      {
                        color = "red";
                        value = item.threshold;
                      }
                    ];
                  };
                };
              };
            }) [
              {
                id = 1;
                title = "Time since complete backup";
                expr = "time() - icloud_photos_backup_last_success_timestamp_seconds{job=\"icloud-photos\"}";
                unit = "s";
                threshold = 43200;
              }
              {
                id = 2;
                title = "Last attempt failed";
                expr = "icloud_photos_backup_failed{job=\"icloud-photos\"}";
                unit = "short";
                threshold = 1;
              }
              {
                id = 3;
                title = "Missing media files";
                expr = "icloud_photos_export_missing{job=\"icloud-photos\"}";
                unit = "short";
                threshold = 1;
              }
              {
                id = 4;
                title = "Export errors";
                expr = "icloud_photos_export_errors{job=\"icloud-photos\"}";
                unit = "short";
                threshold = 1;
              }
              {
                id = 5;
                title = "APFS space used";
                expr = "icloud_photos_apfs_used_ratio{job=\"icloud-photos\"}";
                unit = "percentunit";
                threshold = 0.85;
              }
            ];
          rows = [
            {
              title = "Backup status";
              maxColumnCount = 3;
              panels = [1 2 3 4 5];
              rowHeight = 180;
            }
          ];
        };
      }));
    }
  ];
}
