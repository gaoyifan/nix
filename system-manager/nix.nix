{
  internalSubstituters,
  lib,
  username,
  ...
}: let
  cacheSettings = import ../nix-cache.nix;
in {
  # Determinate manages nix.conf and includes this declarative custom file.
  environment.etc."nix/nix.custom.conf" = {
    text = ''
      extra-substituters = ${lib.concatStringsSep " " (internalSubstituters ++ cacheSettings.extra-substituters)}
      extra-trusted-public-keys = ${lib.concatStringsSep " " cacheSettings.extra-trusted-public-keys}
      extra-trusted-users = ${username}
    '';
    replaceExisting = true;
  };
}
