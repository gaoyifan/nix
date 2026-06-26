{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  cfg = config.services.resticBackup;
in {
  options.services.resticBackup = {
    enable = lib.mkEnableOption "Restic system backup";

    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/home/${username}/nix/secrets/files/home/restic-env";
      description = "Path to the Restic environment file used by the systemd service.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."restic/exclude.txt".text = ''
      *
      !/etc
      !/root
      !/home
      !/srv
      !/opt
      /home/linuxbrew
      /home/${username}/Sync
      /home/${username}/.local/state/syncthing
      .cache
      .bun
      .npm
      .cursor-server
      .rustup
      .antigravity-server
      .venv
      target
    '';

    environment.systemPackages = [
      pkgs.restic
    ];

    systemd.services.restic-backup = {
      description = "Restic Backup";
      wants = ["network-online.target"];
      after = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        EnvironmentFile = cfg.envFile;
        ExecStart = "${lib.getExe pkgs.restic} backup --exclude-file /etc/restic/exclude.txt /";
        # Daily prune can OOM-kill small hosts while repacking the shared repo.
        # Run prune manually or from a larger host when space reclamation is needed.
        ExecStartPost = "${lib.getExe pkgs.restic} forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12";
      };
    };

    systemd.timers.restic-backup = {
      description = "Restic Backup Schedule";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "1h";
        Persistent = true;
        Unit = "restic-backup.service";
      };
    };
  };
}
