# Secrets configuration - base module for NixOS
# This module only defines the filesDir option and imports NixOS secrets.
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
  imports = [
    ./nixos.nix
  ];

  options.services.secrets.filesDir = lib.mkOption {
    type = lib.types.path;
    default = secretsDir;
    description = "Path to the directory containing secret files (real or example)";
    internal = true;
  };
}
