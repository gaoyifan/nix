# Modules shared by all NixOS hosts.
{inputs, ...}: {
  imports = [
    inputs.agenix.nixosModules.default
    ../../secrets
    ./backup.nix
    ./core.nix
    ./home-manager.nix
    ./internal-dns.nix
    ./nix.nix
    ./users.nix
    ./openssh.nix
    ./power.nix
    ./tailscale-gnet.nix
  ];
}
