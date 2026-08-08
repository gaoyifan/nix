# Modules shared by all NixOS hosts.
{inputs, ...}: {
  imports = [
    inputs.agenix.nixosModules.default
    ../../secrets
    ./core.nix
    ./home-manager.nix
    ./nix.nix
    ./users.nix
    ./openssh.nix
    ./power.nix
  ];
}
