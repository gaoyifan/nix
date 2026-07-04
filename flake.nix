{
  description = "Nix configuration for yifan";

  # Binary cache configuration. The personal cache intentionally stores only
  # paths missing from cache.nixos.org, so keep it as a fallback substituter.
  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-cache.yfgao.net?priority=50"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
    ];
  };

  inputs = {
    # Use 26.05 release branches instead of unstable inputs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";
    systems.url = "github:nix-systems/default";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    userborn = {
      url = "github:jfroche/userborn/system-manager";
      inputs.flake-compat.follows = "flake-compat";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    witr = {
      url = "github:pranshuparmar/witr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Use fork with fix for Nix 2.33+ show-derivation JSON format
    # See: https://github.com/serokell/deploy-rs/pull/359
    deploy-rs = {
      url = "github:serokell/deploy-rs/pull/359/head";
      # url = "github:szlend/deploy-rs/fix-show-derivation-parsing";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
      inputs.utils.follows = "flake-utils";
    };

    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
      inputs.userborn.follows = "userborn";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-darwin,
    home-manager,
    nix-darwin,
    deploy-rs,
    system-manager,
    ...
  } @ inputs: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    linuxSystems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    forAllLinuxSystems = nixpkgs.lib.genAttrs linuxSystems;
    resticBackupHosts = [
      "CJIA-GW.gaof.net"
      "bitmagnet"
      "blog"
      "debian21"
      "debian41"
      "do"
      "docker"
      "docker22"
      "el2"
      "el2.gaof.net"
      "gw-el"
      "misc0-61"
      "misc0-sz"
      "misc1"
      "nfs"
      "nfs2"
      "oracle"
    ];
    nixpkgsForSystem = system:
      if nixpkgs.lib.hasSuffix "darwin" system
      then nixpkgs-darwin
      else nixpkgs;
    pkgsFor = system:
      import (nixpkgsForSystem system) {
        inherit system;
        config.allowUnfree = true;
      };
    username = import ./username.nix;
    homeManagerBackupExtension = "backup-$(date +%Y%m%d-%H%M%S)";
    darwinHosts = [
      "Yifans-MacBook-Air-2022"
      "YifansMacStudio"
      "Yans-Mac-mini"
      "openclaw"
      "default"
    ];
    overlay = final: prev: import ./pkgs prev;
    # NixOS host builder: shared nixpkgs setup, common modules, and
    # home-manager integration. Hosts only list their own modules.
    mkNixosHost = system: hostModules:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs username;};
        modules =
          [
            {
              nixpkgs.overlays = [overlay];
              nixpkgs.config.allowUnfree = true;
            }
            ./nixos/common
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {inherit inputs;};
                users.${username} = {pkgs, ...}: {
                  imports = [./home-manager];
                  home.packages = [home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default];
                  services.mutagen.dotfileSync.enable = false;
                };
              };
            }
          ]
          ++ hostModules;
      };
    mkDeployNode = system: hostname: nixosConfig: {
      inherit hostname;
      sshUser = "root";
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.${system}.activate.nixos nixosConfig;
        remoteBuild = true;
      };
    };
    mkLinuxSystemConfig = system: extraModules:
      system-manager.lib.makeSystemConfig {
        overlays = [overlay];
        specialArgs = {inherit username;};
        modules =
          [
            ./system-manager/restic.nix
            # system-manager imports NixOS nginx without the full NixOS module
            # list. This nixpkgs pin's nginx still references security.dhparams;
            # drop this once the pin has nginx sslDhparam removed or system-manager
            # imports the matching dependency itself.
            "${nixpkgs}/nixos/modules/security/dhparams.nix"
            ({pkgs, ...}: {
              nixpkgs.hostPlatform = system;
              nixpkgs.config.allowUnfree = true;
              environment.systemPackages = [
                pkgs.tsshd
              ];
            })
          ]
          ++ extraModules;
      };
  in {
    # Custom packages: nix build .#lazyssh
    packages = forAllSystems (system: let
      packages = import ./pkgs (pkgsFor system);
    in
      packages
      // {
        copilot = packages.copilot-cli;
        cursor-agent = packages.cursor-cli;
        difftastic = (pkgsFor system).difftastic;
        fd = (pkgsFor system).fd;
        yazi = (pkgsFor system).yazi-unwrapped;
      }
      // nixpkgs.lib.optionalAttrs (!(nixpkgs.lib.hasSuffix "darwin" system)) {
        system-manager = system-manager.packages.${system}.default;
      });

    # On-demand CLI apps used by _nix_app aliases to keep Home Manager closures small.
    # Every name maps to the same-named flake package; extra aliases are added at the end.
    apps = forAllSystems (system: let
      packages = self.packages.${system};
      mkApp = name: {
        type = "app";
        program = nixpkgs.lib.getExe packages.${name};
        meta = packages.${name}.meta;
      };
      cliApps =
        nixpkgs.lib.genAttrs [
          "agy"
          "codex"
          "copilot"
          "copilot-cli"
          "cursor-agent"
          "cursor-cli"
          "difftastic"
          "fd"
          "yazi"
        ]
        mkApp;
    in
      cliApps);

    # nix fmt
    formatter = forAllSystems (system: (nixpkgsForSystem system).legacyPackages.${system}.alejandra);

    # Overlay to make custom packages available as pkgs.lazyssh
    overlays.default = overlay;

    # nix develop
    devShells = forAllSystems (system: {
      default = import ./shell.nix {
        pkgs = (nixpkgsForSystem system).legacyPackages.${system};
        inherit home-manager nix-darwin deploy-rs;
      };
    });

    # Standalone home-manager for non-darwin systems
    # Usage: home-manager switch --flake .#yifan
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
            ./home-manager
            {home.username = username;}
          ];
        };
      });

    # macOS system configuration with integrated home-manager
    # Usage: darwin-rebuild switch --flake .
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
          modules = [
            # Apply overlay and allow unfree packages
            {
              nixpkgs.hostPlatform = "aarch64-darwin";
              nixpkgs.overlays = [overlay];
              nixpkgs.config.allowUnfree = true;
            }
            ./darwin/configuration.nix

            # Integrate home-manager as a darwin module
            home-manager.darwinModules.home-manager
            ({pkgs, ...}: {
              home-manager = {
                useGlobalPkgs = true; # Use system nixpkgs instead of standalone
                useUserPackages = true; # Install to /etc/profiles instead of ~/.nix-profile
                backupCommand = pkgs.writeShellScript "home-manager-backup" ''
                  target="$1"
                  [ -n "$target" ] && mv "$target" "$target.${homeManagerBackupExtension}"
                '';
                extraSpecialArgs = {inherit inputs;};
                users.${username} = import ./home-manager;
              };
            })
          ];
        }
    );

    # NixOS configurations
    nixosConfigurations = {
      somo-minisforum = mkNixosHost "x86_64-linux" [./nixos/hosts/somo-minisforum];
    };

    # Linux system configuration for non-NixOS hosts.
    # Usage: system-manager switch --flake .
    systemConfigs = forAllLinuxSystems (
      system:
        {
          default = mkLinuxSystemConfig system [];
        }
        // nixpkgs.lib.genAttrs resticBackupHosts (_host:
          mkLinuxSystemConfig system [
            {services.resticBackup.enable = true;}
          ])
    );

    # deploy-rs configuration
    deploy.nodes.somo-minisforum = mkDeployNode "x86_64-linux" "somo-minisforum.ts.gaof.net" self.nixosConfigurations.somo-minisforum;
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
  };
}
