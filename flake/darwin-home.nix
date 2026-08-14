{
  inputs,
  username,
  forAllSystems,
  nixpkgs,
  overlay,
  mkHomeManagerBackupCommand,
  home-manager,
  nix-darwin,
  ...
}: let
  darwinHosts = [
    "Yifans-MacBook-Air-2022"
    "YifansMacStudio"
    "Yans-Mac-mini"
    "openclaw"
    "default"
  ];
in {
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

  darwinConfigurations = nixpkgs.lib.genAttrs darwinHosts (
    hostname:
      nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit inputs username;
          darwinProfile =
            if hostname == "openclaw"
            then "openclaw"
            else if hostname == "YifansMacStudio"
            then "yifansmacstudio"
            else "default";
        };
        modules =
          [
            {
              networking.hostName = nixpkgs.lib.mkIf (hostname != "default") hostname;
              nixpkgs.hostPlatform = "aarch64-darwin";
              nixpkgs.overlays = [overlay];
              nixpkgs.config.allowUnfree = true;
            }
            ../darwin/configuration.nix
            ../darwin/auto-pause-cemu.nix
            home-manager.darwinModules.home-manager
            ({pkgs, ...}: {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupCommand = mkHomeManagerBackupCommand pkgs;
                extraSpecialArgs = {
                  inherit inputs;
                  darwinHost = hostname;
                };
                users.${username} = import ../home-manager;
              };
            })
          ]
          ++ nixpkgs.lib.optional (hostname == "YifansMacStudio") ../darwin/whisper-server.nix;
      }
  );
}
