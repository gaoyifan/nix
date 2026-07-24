# Modules shared by all NixOS hosts.
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
