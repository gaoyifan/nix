{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.secrets;
in {
  options.services.secrets = {
    atuin = {
      enable = mkEnableOption "Atuin sync key deployment";

      keyFile = mkOption {
        type = types.path;
        # Use the detected secrets directory
        default = "${cfg.filesDir}/home/atuin-key";
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
