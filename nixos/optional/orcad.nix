{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  cfg = config.services.orcad;
  hostname = "${cfg.tailscaleServiceName}.ts.gaof.net";
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [./acme-certificates.nix];

  options.services.orcad.tailscaleServiceName = lib.mkOption {
    type = lib.types.nonEmptyStr;
    default = "orcad";
    description = "Tailscale Service name, also used as the hostname under ts.gaof.net.";
  };

  config = {
    services.acmeCertificates = {
      enable = true;
      restartServices = lib.mkAfter ["tailscale-serve"];
    };
    services.tailscale.serve.enable = true;
    services.tailscale.serve.services.${cfg.tailscaleServiceName} = {
      certificate = {
        certFile = "${certDir}/fullchain.pem";
        keyFile = "${certDir}/privkey.pem";
      };
      tlsEndpoints."tcp:443" = "http://127.0.0.1:6768";
    };

    systemd.services.orcad = {
      description = "Orca headless agent runtime";
      wantedBy = ["multi-user.target"];
      # Activate upgrades on manual restart; avoid client disconnects during NixOS switches.
      restartIfChanged = false;
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
  };
}
