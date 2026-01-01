# Development shell for working on this flake
# Provides: nh, nil (LSP), alejandra (formatter), just, home-manager, darwin-rebuild
{
  pkgs,
  home-manager,
  nix-darwin,
}:
pkgs.mkShell {
  packages =
    [
      pkgs.nh
      pkgs.nil
      pkgs.alejandra
      pkgs.just
      home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
      nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
}
