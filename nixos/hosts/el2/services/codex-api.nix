{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.codex-api;
  stateDirectory = "/pool1/services/codex-api";
in {
  imports = [../../../optional/codex-api.nix];

  config = lib.mkIf cfg.enable {
    age.secrets.el2-codex-api-auth = {
      file = config.services.secrets.filesDir + "/nixos/el2/codex-api-auth.age";
      owner = cfg.user;
      group = cfg.group;
    };

    services.codex-api = {
      settings = {
        server.listen = "0.0.0.0:3003";
        state.path = "${stateDirectory}/state.sqlite3";
        upstream.auth_file = config.age.secrets.el2-codex-api-auth.path;
      };
    };

    systemd.services.codex-api = {
      wantedBy = lib.mkForce ["el2-services.target"];
      requires = ["zfs-unlock-mount.service"];
      after = ["zfs-unlock-mount.service"];
      restartTriggers = lib.mkIf config.services.secrets.hasRealFiles (
        [config.age.secrets.el2-codex-api-auth.file] ++ lib.attrValues cfg.sharedTokenFiles
      );
      serviceConfig = {
        ExecStartPre = "+${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${stateDirectory}";
      };
    };
  };
}
