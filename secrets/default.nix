# Secrets configuration - base module for NixOS
# This module only defines the filesDir option.
# home-manager imports secrets/home.nix directly for home-manager-specific secrets.
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
in {
  options.services.secrets = {
    filesDir = lib.mkOption {
      type = lib.types.path;
      default = secretsDir;
      description = "Path to the directory containing secret files (real or example)";
      internal = true;
    };

    nixos."somo-minisforum".vms = lib.mkOption {
      type = lib.types.attrs;
      default = import (secretsDir + "/nixos/somo-minisforum/vms.nix");
      description = "Declarative Incus VM definitions for somo-minisforum.";
      internal = true;
    };

    nixos."somo-minisforum".wgEl2 = lib.mkOption {
      type = lib.types.attrs;
      default =
        import (secretsDir + "/nixos/somo-minisforum/wg-el2.nix")
        // {
          privateKeyFile = "${config.services.secrets.filesDir}/nixos/somo-minisforum/wg-el2-private-key";
        };
      description = "WireGuard EL2 egress configuration for somo-minisforum.";
      internal = true;
    };

    nixos.wlt.sshHostKeyFile = lib.mkOption {
      type = lib.types.path;
      default = secretsDir + "/nixos/wlt-ssh-host-key";
      description = "Shared SSH host private key for the WLT selector service.";
      internal = true;
    };
  };
}
