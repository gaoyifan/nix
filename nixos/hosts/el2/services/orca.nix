{
  config,
  pkgs,
  username,
  ...
}: let
  hostname = "orcad.ts.gaof.net";
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  services.tailscale.serve.services.orcad = {
    certificate = {
      certFile = "${certDir}/fullchain.pem";
      keyFile = "${certDir}/privkey.pem";
    };
    tlsEndpoints."tcp:443" = "http://127.0.0.1:6768";
  };

  systemd.services.orcad = {
    description = "Orca headless agent runtime";
    wantedBy = ["multi-user.target"];
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
      ExecStart = "${pkgs.orcad}/bin/orcad --port 6768 --pairing-address https://${hostname} --json";
      Restart = "on-failure";
      RestartSec = "5s";
      RestartPreventExitStatus = [78];
      UMask = "0077";
    };
  };
}
