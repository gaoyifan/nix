{hostname}: let
  # Keep platform modules independent of whether the private secrets submodule
  # is available; CI and fresh clones transparently use the example fallback.
  hasRealSecrets = builtins.pathExists ./files/.gitkeep;
  secretsDir =
    if hasRealSecrets
    then ./files
    else ./files-example;
in
  (import (secretsDir + "/nixos/internal-substituters.nix") {
    inherit hostname;
  }).substituters
