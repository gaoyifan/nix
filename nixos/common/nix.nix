# Nix daemon settings and disk cleanup shared by all hosts.
{
  config,
  lib,
  username,
  ...
}: {
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    substituters = lib.mkBefore config.services.secrets.nixos.internalSubstituters;
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
