{
  inputs,
  username,
  nixpkgs,
  overlay,
  mkHomeManagerBackupCommand,
  home-manager,
  nix-darwin,
  ...
}: {
  darwinConfigurations =
    nixpkgs.lib.genAttrs [
      "yifans-mba-2022"
      "yifans-mac-studio"
      "default"
    ] (
      hostname:
        nix-darwin.lib.darwinSystem {
          specialArgs = {inherit inputs username;};
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
                  users.${username} = {
                    imports = [../home-manager];
                    services.mutagen.dotfileSync.syncCodexSessions = builtins.elem hostname [
                      "yifans-mba-2022"
                      "yifans-mac-studio"
                    ];
                  };
                };
              })
            ]
            ++ nixpkgs.lib.optional (hostname == "yifans-mac-studio") ../darwin/whisper-server.nix;
        }
    );
}
