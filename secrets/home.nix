# Home-manager secrets configuration
{
  config,
  lib,
  ...
}: let
  realSecretsDir = ./files;
  exampleSecretsDir = ./files-example;
  hasRealSecrets = builtins.pathExists (realSecretsDir + "/.gitkeep");
  hasAtuinSecrets =
    hasRealSecrets
    && builtins.pathExists (realSecretsDir + "/home/atuin-key")
    && builtins.pathExists (realSecretsDir + "/home/atuin-password");
  secretsDir =
    if hasRealSecrets
    then realSecretsDir
    else exampleSecretsDir;
  cfg = config.services.secrets;
in {
  options.services.secrets = {
    hasRealFiles = lib.mkOption {
      type = lib.types.bool;
      default = hasRealSecrets;
      description = "Whether the real secrets submodule is available locally";
      internal = true;
      readOnly = true;
    };

    filesDir = lib.mkOption {
      type = lib.types.path;
      default = secretsDir;
      description = "Path to the directory containing secret files";
      internal = true;
    };

    atuin = {
      enable = lib.mkEnableOption "Atuin sync key deployment";
      available = lib.mkOption {
        type = lib.types.bool;
        default = hasAtuinSecrets;
        description = "Whether real Atuin credentials are available locally";
        internal = true;
        readOnly = true;
      };
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

  config = lib.mkIf (cfg.atuin.enable && cfg.atuin.available) {
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
