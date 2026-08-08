# User accounts shared by all hosts. Fully declarative; remote access is via
# SSH keys only (password authentication is disabled in openssh.nix).
{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  inherit (import ./ssh-keys.nix) sshKeys;
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    root-password-hash.file = config.services.secrets.filesDir + "/nixos/root-password-hash.age";
  };

  users.mutableUsers = false;

  # Shared root password from the secrets submodule, effectively usable on
  # the local console only since SSH password logins are disabled. Root SSH
  # key access is what deploy-rs and remote nixos-rebuild use.
  users.users.root = {
    hashedPasswordFile = "/run/agenix/root-password-hash";
    openssh.authorizedKeys.keys = sshKeys;
  };

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = ["wheel"];
    linger = true;
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = sshKeys;
  };

  security.sudo.wheelNeedsPassword = false;
}
