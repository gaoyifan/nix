{
  self,
  forAllSystems,
  nixpkgsForSystem,
  home-manager,
  nix-darwin,
  deploy-rs,
  ...
}: {
  devShells = forAllSystems (system: {
    default = import ../shell.nix {
      pkgs = (nixpkgsForSystem system).legacyPackages.${system};
      formatter = self.formatter.${system};
      inherit home-manager nix-darwin deploy-rs;
    };
  });
}
