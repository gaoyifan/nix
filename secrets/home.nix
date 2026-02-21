# Home-manager secrets configuration
{
  config,
  lib,
  ...
}: let
  hasRealSecrets = builtins.pathExists ./files/.gitkeep;
  secretsDir =
    if hasRealSecrets
    then ./files
    else ./files-example;
  cfg = config.services.secrets;
in {
  options.services.secrets = {
    filesDir = lib.mkOption {
      type = lib.types.path;
      default = secretsDir;
      description = "Path to the directory containing secret files";
      internal = true;
    };

    atuin = {
      enable = lib.mkEnableOption "Atuin sync key deployment";
      keyFile = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.filesDir}/home/atuin-key";
        description = "Path to the Atuin encryption key file";
      };
      passwordFile = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.filesDir}/home/atuin-password";
        description = "Path to the Atuin password file";
      };
    };

    restic = {
      envFile = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.filesDir}/home/restic-env";
        description = "Path to the Restic environment file for systemd EnvironmentFile";
      };
    };
  };

  config = lib.mkIf cfg.atuin.enable {
    home.file.".local/share/atuin/key" = {
      source = cfg.atuin.keyFile;
      force = true;
    };
    home.file.".local/share/atuin/password" = {
      source = cfg.atuin.passwordFile;
      force = true;
    };
  };
}
