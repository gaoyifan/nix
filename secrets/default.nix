{
  config,
  lib,
  ...
}: let
  # Select secrets module based on whether submodule is initialized
  # CI builds don't have submodule access, so they use secrets-example
  # Note: Check for a marker file inside the submodule. checking .git fails because Nix filters it out.
  hasRealSecrets = builtins.pathExists ./files/.gitkeep;
  secretsDir =
    if hasRealSecrets
    then ./files
    else ./files-example;
in {
  imports = [./home.nix];

  options.services.secrets.filesDir = lib.mkOption {
    type = lib.types.path;
    default = secretsDir;
    description = "Path to the directory containing secret files (real or example)";
    internal = true;
  };
}
