{
  inputs,
  username,
  forAllSystems,
  nixpkgs,
  overlay,
  home-manager,
  ...
}: {
  legacyPackages = forAllSystems (system:
    if nixpkgs.lib.hasSuffix "darwin" system
    then {}
    else {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          overlays = [overlay];
          config.allowUnfree = true;
        };
        extraSpecialArgs = {inherit inputs;};
        modules = [
          ../home-manager
          {home.username = username;}
        ];
      };
    });
}
