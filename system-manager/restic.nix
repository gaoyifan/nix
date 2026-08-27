{
  lib,
  pkgs,
  username,
  ...
}: {
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
      EnvironmentFile = "/home/${username}/.config/restic/env";
      ExecStart = "${lib.getExe pkgs.restic} backup --exclude-file /etc/restic/exclude.txt /";
    };
  };

  systemd.timers.restic-backup = {
    description = "Restic Backup Schedule";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };
}
