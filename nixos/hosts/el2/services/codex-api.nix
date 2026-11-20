{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  cfg = config.services.codex-api;
  stateDirectory = "/pool1/services/codex-api";
in {
  imports = [../../../optional/codex-api.nix];

  config = lib.mkIf cfg.enable {
    services.codex-api = {
      settings = {
        server.listen = "127.0.0.1:3003";
        state.path = "${stateDirectory}/state.sqlite3";
        upstream.auth_file = "/run/credentials/codex-api.service/auth.json";
      };
      ageApiKeys = [
        {
          id = "honcho";
          secretName = "honcho-api-token";
        }
      ];
    };

    systemd.services.codex-api = {
      wantedBy = lib.mkForce ["el2-services.target"];
      requires = ["zfs-unlock-mount.service"];
      after = ["zfs-unlock-mount.service"];
      restartTriggers = [config.age.secrets.honcho-api-token.file];
      serviceConfig = {
        LoadCredential = "auth.json:${config.users.users.${username}.home}/.codex-api/auth.json";
        ExecStartPre = "+${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${stateDirectory}";
      };
    };
  };
}
