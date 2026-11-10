{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  hasSecrets = config.services.secrets.hasRealFiles;
  stateDirectory = "/pool1/services/codex-api";
in {
  imports = [../../../optional/codex-api.nix];

  config = lib.mkIf hasSecrets {
    services.codex-api.settings = {
      server.listen = "127.0.0.1:3003";
      state.path = "${stateDirectory}/state.sqlite3";
      upstream.auth_file = "/run/credentials/codex-api.service/auth.json";
      api_keys = [
        {
          id = "honcho";
          secret_file = config.age.secrets.honcho-api-token.path;
          weekly_limit_usd = "500.00";
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
        ExecStartPre = "+${pkgs.coreutils}/bin/install -d -m 0700 -o codex-api -g codex-api ${stateDirectory}";
      };
    };
  };
}
