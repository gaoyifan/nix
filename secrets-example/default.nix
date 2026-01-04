# Secrets Module - Example/Placeholder
# This module provides placeholder secrets for CI builds.
# For production, use the private `secrets/` submodule with the same interface.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.secrets;
  secretsDir = ./.;
in {
  options.services.secrets = {
    atuin = {
      enable = mkEnableOption "Atuin sync key deployment";

      keyFile = mkOption {
        type = types.path;
        default = "${secretsDir}/atuin/key";
        description = "Path to the Atuin encryption key file";
      };
    };
  };

  config = mkIf cfg.atuin.enable {
    # Deploy atuin key to user's data directory
    home.file.".local/share/atuin/key" = {
      source = cfg.atuin.keyFile;
      force = true; # Overwrite existing key file
    };
  };
}
