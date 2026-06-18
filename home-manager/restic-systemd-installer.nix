# Restic utilities for home-manager
{
  config,
  lib,
  pkgs,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  homeDir = config.home.homeDirectory;
  resticBin = "${homeDir}/.nix-profile/bin/restic";
  resticConfigDir = "${homeDir}/.config/restic-systemd";
  # Keep the Restic environment file outside the Nix store so real secrets do
  # not depend on whether the secrets submodule is included in the flake source.
  resticEnvFile = "${homeDir}/nix/secrets/files/home/restic-env";
in
  lib.mkIf (!isDarwin) (let
    resticExcludeContent = ''
      *
      !/etc
      !/root
      !/home
      !/srv
      !/opt
      /home/linuxbrew
      /home/yifan/Sync
      /home/yifan/.local/state/syncthing
      .cache
      .bun
      .npm
      .cursor-server
      .rustup
      .antigravity-server
      .venv
      target
    '';
    resticServiceContent = ''
      [Unit]
      Description=Restic Backup
      Wants=network-online.target
      After=network-online.target

      [Service]
      Type=oneshot
      User=root
      Group=root
      EnvironmentFile=${resticEnvFile}
      ExecStart=${resticBin} backup --exclude-file ${resticConfigDir}/restic-exclude.txt /
      # Daily prune can OOM-kill small hosts while repacking the shared repo.
      # Run prune manually or from a larger host when space reclamation is needed.
      ExecStartPost=${resticBin} forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12
    '';
    resticTimerContent = ''
      [Unit]
      Description=Restic Backup Schedule

      [Timer]
      OnCalendar=daily
      RandomizedDelaySec=1h
      Persistent=true
      Unit=restic-backup.service

      [Install]
      WantedBy=timers.target
    '';
    resticSystemdInstaller = pkgs.writeShellApplication {
      name = "restic-install-systemd-timer";
      text = ''
        set -euo pipefail

        if [ "$#" -ne 0 ]; then
          echo "No arguments supported." >&2
          exit 1
        fi

        if [ "$(id -u)" -ne 0 ]; then
          exec sudo -- "$0"
        fi

        test -f "${resticEnvFile}"
        test -x "${resticBin}"
        test -f "${resticConfigDir}/restic-backup.service"
        test -f "${resticConfigDir}/restic-backup.timer"

        ln -sfn ${resticConfigDir}/restic-backup.service /etc/systemd/system/restic-backup.service
        ln -sfn ${resticConfigDir}/restic-backup.timer /etc/systemd/system/restic-backup.timer

        systemctl daemon-reload
        systemctl enable --now restic-backup.timer
      '';
    };
  in {
    home.file.".config/restic-systemd/restic-backup.service".text = resticServiceContent;
    home.file.".config/restic-systemd/restic-backup.timer".text = resticTimerContent;
    home.file.".config/restic-systemd/restic-exclude.txt".text = resticExcludeContent;

    home.packages = [
      resticSystemdInstaller
    ];
  })
