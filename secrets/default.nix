# Shared secret source selection for NixOS.
# Individual consumers declare their own age.secrets entries next to the
# service configuration that uses them.
{
  config,
  lib,
  ...
}: let
  hasRealFiles = builtins.pathExists ./files/.gitkeep;
  filesDir =
    if hasRealFiles
    then ./files
    else ./files-example;
  mail = import (filesDir + "/nixos/mail.nix");
in {
  # Public/CI builds may evaluate with example metadata, but must not replace
  # a running host's configuration without its encrypted secrets submodule.
  config.system.switch.enable = config.services.secrets.hasRealFiles;

  options.services.secrets = {
    hasRealFiles = lib.mkOption {
      type = lib.types.bool;
      default = hasRealFiles;
      readOnly = true;
      internal = true;
      description = "Whether the encrypted secrets submodule is available.";
    };

    filesDir = lib.mkOption {
      type = lib.types.path;
      default = filesDir;
      internal = true;
      description = "Directory containing private metadata and encrypted files.";
    };

    mail = lib.mkOption {
      type = lib.types.submodule {
        options = {
          smtpUser = lib.mkOption {
            type = lib.types.str;
          };
          senders = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
          };
          znapzendErrorSummaryTo = lib.mkOption {
            type = lib.types.str;
          };
        };
      };
      default = mail;
      readOnly = true;
      internal = true;
      description = "Private mail addresses used by system services.";
    };
  };
}
