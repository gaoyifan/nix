{
  inputs,
  username,
  forAllSystems,
  nixpkgs,
  overlay,
  home-manager,
  ...
}: let
  codexSessionSyncHosts = [
    "debian41"
    "debian42"
  ];
in {
  legacyPackages = forAllSystems (system:
    if nixpkgs.lib.hasSuffix "darwin" system
    then {}
    else {
      homeConfigurations =
        nixpkgs.lib.genAttrs (
          [username]
          ++ map (host: "${username}@${host}") codexSessionSyncHosts
        ) (name:
          home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              inherit system;
              overlays = [overlay];
              config.allowUnfree = true;
            };
            extraSpecialArgs = {inherit inputs;};
            modules = [
              ../home-manager
              {
                home.username = username;
                services.mutagen.dotfileSync.syncCodexSessions = name != username;
              }
            ];
          });
    });
}
