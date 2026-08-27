# Home-manager secrets configuration
{
  config,
  lib,
  pkgs,
  darwinHost ? null,
  ...
}: let
  realSecretsDir = ./files;
  hasRealSecrets = builtins.pathExists (realSecretsDir + "/.gitkeep");
  hasRegisteredUserKey =
    !pkgs.stdenv.isDarwin
    || darwinHost == "yifans-mba-2022";
  hasAtuinSecrets =
    hasRealSecrets
    && hasRegisteredUserKey
    && builtins.pathExists (realSecretsDir + "/home/atuin-key.age")
    && builtins.pathExists (realSecretsDir + "/home/atuin-password.age");
  hasResticSecrets =
    hasRealSecrets
    && hasRegisteredUserKey
    && builtins.pathExists (realSecretsDir + "/home/restic-env.age");
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
        type = lib.types.str;
        default =
          if hasAtuinSecrets
          then config.age.secrets."atuin-key".path
          else "/run/agenix/atuin-key";
        description = "Path to the Atuin encryption key file";
      };
      passwordFile = lib.mkOption {
        type = lib.types.str;
        default =
          if hasAtuinSecrets
          then config.age.secrets."atuin-password".path
          else "/run/agenix/atuin-password";
        description = "Path to the Atuin password file";
      };
    };

    restic = {
      envFile = lib.mkOption {
        type = lib.types.str;
        default =
          if hasResticSecrets
          then config.age.secrets."restic-env".path
          else "${config.home.homeDirectory}/.config/restic/env";
        description = "Path to the Restic environment file for systemd EnvironmentFile";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (pkgs.stdenv.isDarwin && (hasAtuinSecrets || hasResticSecrets)) {
      # launchd ORs KeepAlive conditions, so agenix's additional
      # Crashed = false condition restarts the agent after successful exits.
      launchd.agents.activate-agenix.config.KeepAlive = lib.mkForce {
        SuccessfulExit = false;
      };
    })
    (lib.mkIf (cfg.atuin.enable && cfg.atuin.available) {
      age.secrets = {
        "atuin-key" = {
          file = realSecretsDir + "/home/atuin-key.age";
          path = "${config.home.homeDirectory}/.local/share/atuin/key";
          mode = "0600";
        };
        "atuin-password" = {
          file = realSecretsDir + "/home/atuin-password.age";
          path = "${config.home.homeDirectory}/.local/share/atuin/password";
          mode = "0600";
        };
      };
    })
    (lib.mkIf hasResticSecrets {
      age.secrets."restic-env" = {
        file = realSecretsDir + "/home/restic-env.age";
        path = "${config.home.homeDirectory}/.config/restic/env";
        mode = "0600";
      };
    })
  ];
}
