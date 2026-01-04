# Development shell for working on this flake
# Provides: nh, nil (LSP), alejandra (formatter), just, home-manager, darwin-rebuild
{
  pkgs,
  pkgsUnstable,
  home-manager,
  nix-darwin,
  deploy-rs,
}:
pkgs.mkShell {
  packages =
    [
      pkgs.nh
      pkgs.nil
      pkgs.alejandra
      pkgsUnstable.just
      deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
      home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
      nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
}
