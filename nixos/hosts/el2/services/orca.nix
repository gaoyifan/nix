{
  pkgs,
  username,
  ...
}: let
  address = "100.127.100.2";
in {
  systemd.services.orcad = {
    description = "Orca headless agent runtime";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target" "tailscaled.service"];
    after = ["network-online.target" "tailscaled.service"];
    path = [pkgs.orcad pkgs.codex pkgs.git pkgs.openssh pkgs.bash];
    environment = {
      CODEX_HOME = "/home/${username}/.syncd-dotfiles/.codex";
      ORCA_USER_DATA = "/var/lib/orca";
      ORCA_USER_DATA_PATH = "/var/lib/orca";
      ORCA_TELEMETRY_DISABLED = "1";
    };
    serviceConfig = {
      User = username;
      StateDirectory = "orca";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/orca";
      ExecStart = "${pkgs.orcad}/bin/orcad --bind ${address} --port 6768 --pairing-address ${address} --json";
      Restart = "on-failure";
      RestartSec = "5s";
      RestartPreventExitStatus = [78];
      UMask = "0077";
    };
  };
}
