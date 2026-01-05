# PPPoE WAN configuration using service secrets
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.router;
  secrets = config.services.secrets.nixos.${config.networking.hostName};
in
  lib.mkIf cfg.pppoe.enable {
    # PPPoE service using secret config files
    environment.etc = {
      "ppp/peers/${cfg.pppoe.peerName}".source = secrets.pppoe.peerFile;
      "ppp/chap-secrets".source = secrets.pppoe.chapSecretsFile;
      "ppp/pap-secrets".source = secrets.pppoe.papSecretsFile;
    };

    systemd.services.pppoe-wan = {
      description = "PPPoE WAN Connection";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "systemd-networkd.service"];
      wants = ["systemd-networkd.service"];

      path = [pkgs.ppp];

      script = ''
        exec ${pkgs.ppp}/bin/pppd call ${cfg.pppoe.peerName}
      '';

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  }
