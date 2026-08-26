{
  inputs,
  username,
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
  codexSessionSyncHosts = [
    "Yifans-MacBook-Air-2022"
    "YifansMacStudio"
  ];
in {
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
                users.${username} = {
                  imports = [../home-manager];
                  services.mutagen.dotfileSync.syncCodexSessions = builtins.elem hostname codexSessionSyncHosts;
                };
              };
            })
          ]
          ++ nixpkgs.lib.optional (hostname == "YifansMacStudio") ../darwin/whisper-server.nix;
      }
  );
}
