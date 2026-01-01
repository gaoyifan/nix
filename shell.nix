# Development shell configuration
# Split from flake.nix for cleaner organization
{
  pkgs,
  home-manager,
  nix-darwin,
}:
pkgs.mkShell {
  packages = [
    pkgs.nh
    pkgs.nil
    pkgs.just
    home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
    nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
