# Nix daemon settings and disk cleanup shared by all hosts.
{
  config,
  lib,
  username,
  ...
}: let
  cacheSettings = import ../../nix-cache.nix;
  internalSubstituters = import ../../secrets/internal-substituters.nix {
    hostname = config.networking.hostName;
  };
in {
  nix.channel.enable = false;

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    substituters = lib.mkForce (
      internalSubstituters
      ++ cacheSettings.extra-substituters
      ++ [cacheSettings.official-substituter]
    );
    trusted-public-keys = lib.mkForce (
      cacheSettings.extra-trusted-public-keys
      ++ [cacheSettings.official-public-key]
    );
    trusted-users = [username];
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
