# Development shell for working on this flake
# Provides: nh, nil (LSP), alejandra (formatter), just, home-manager, darwin-rebuild
{
  pkgs,
  home-manager,
  nix-darwin,
  deploy-rs,
}:
pkgs.mkShell {
  packages =
    [
      pkgs.nh
      pkgs.nil
      pkgs.nixd
      pkgs.alejandra
      pkgs.just
      deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
      home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
      nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
}
