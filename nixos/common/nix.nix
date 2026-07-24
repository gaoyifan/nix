# Nix daemon settings and disk cleanup shared by all hosts.
{
  config,
  lib,
  username,
  ...
}: let
  cacheSettings = import ../../nix-cache.nix;
in {
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    extra-substituters =
      config.services.secrets.nixos.internalSubstituters
      ++ cacheSettings.extra-substituters;
    extra-trusted-public-keys = cacheSettings.extra-trusted-public-keys;
    trusted-users = ["root" username];
    # Free disk space automatically when the store partition runs low.
    min-free = lib.mkDefault (2 * 1024 * 1024 * 1024);
    max-free = lib.mkDefault (6 * 1024 * 1024 * 1024);
  };

  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "daily";
    options = lib.mkDefault "--delete-older-than 30d";
  };
}
