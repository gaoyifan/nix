# Modules shared by all NixOS hosts.
# Defaults use lib.mkDefault so hosts can override; hosts use lib.mkForce
# when they need to replace a shared list (e.g. substituters).
{...}: {
  imports = [
    ../../secrets
    ./core.nix
    ./home-manager.nix
    ./nix.nix
    ./users.nix
    ./openssh.nix
    ./power.nix
  ];
}
