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
    };
  };

  config = lib.mkIf cfg.atuin.enable {
    home.file.".local/share/atuin/key" = {
      source = cfg.atuin.keyFile;
      force = true;
    };
  };
}
