{
  description = "Nix configuration for yifan";

  # Binary cache configuration - prioritize personal cache for faster builds
  nixConfig = {
    substituters = [
      "https://nix-cache.yfgao.net"
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  inputs = {
    # Keep nix-darwin and Home Manager on the same moving nixpkgs to avoid
    # carrying a second unstable package set through the flake.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
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
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nix-darwin,
    deploy-rs,
    ...
  } @ inputs: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    pkgsFor = system:
      import nixpkgs {
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
  in {
    # Custom packages: nix build .#lazyssh
    packages = forAllSystems (system: let
      packages = import ./pkgs (pkgsFor system);
    in
      packages
      // {
        agy = packages.antigravity-cli;
        cursor-agent = packages.cursor-cli;
      });

    # Runnable apps: nix run .#codex / nix run .#cursor-agent / nix run .#agy
    apps = forAllSystems (system: let
      packages = self.packages.${system};
      agy = {
        type = "app";
        program = nixpkgs.lib.getExe packages.agy;
        meta = packages.agy.meta;
      };
      cursorAgent = {
        type = "app";
        program = nixpkgs.lib.getExe packages.cursor-agent;
        meta = packages.cursor-agent.meta;
      };
    in {
      inherit agy;
      antigravity = agy;
      antigravity-cli = agy;
      codex = {
        type = "app";
        program = nixpkgs.lib.getExe packages.codex;
        meta = packages.codex.meta;
      };
      cursor-agent = cursorAgent;
      cursor-cli = cursorAgent;
    });

    # nix fmt
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Overlay to make custom packages available as pkgs.lazyssh
    overlays.default = overlay;

    # nix develop
    devShells = forAllSystems (system: {
      default = import ./shell.nix {
        pkgs = nixpkgs.legacyPackages.${system};
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
      exp0 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit username;};
        modules = [
          ./nixos/exp0
        ];
      };
    };

    # deploy-rs configuration
    deploy.nodes.exp0 = {
      hostname = "nixos-exp0";
      sshUser = "root";
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.exp0;
        remoteBuild = true;
      };
    };
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
  };
}
