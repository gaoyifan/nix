# Development shell for working on this flake
# Provides Nix tooling, the repository formatter, and configuration switch commands.
{
  pkgs,
  formatter,
  home-manager,
  nix-darwin,
  deploy-rs,
}:
pkgs.mkShell {
  packages =
    [
      pkgs.nix
      pkgs.nh
      pkgs.nil
      pkgs.nixd
      pkgs.just
      formatter
      deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
      home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
      nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
}
