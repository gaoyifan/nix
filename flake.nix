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
    self.submodules = true;
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.11";
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
    username = "yifan";
    darwinHosts = [
      "Yifans-MacBook-Air-2022"
      "Yifans-Mac-Studio"
      "default"
    ];
    overlay = final: prev: import ./pkgs prev;
  in {
    # Custom packages: nix build .#lazyssh
    packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});

    # nix fmt
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Overlay to make custom packages available as pkgs.lazyssh
    overlays.default = overlay;

    # nix develop
    devShells = forAllSystems (system: {
      default = import ./shell.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        pkgsUnstable = inputs.nixpkgs-unstable.legacyPackages.${system};
        inherit home-manager nix-darwin deploy-rs;
      };
    });

    # Standalone home-manager for non-darwin systems
    # Usage: home-manager switch --flake .#yifan
    legacyPackages = forAllSystems (system: {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          overlays = [overlay];
          config.allowUnfree = true;
        };
        extraSpecialArgs = {inherit inputs;};
        modules = [./home-manager];
      };
    });

    # macOS system configuration with integrated home-manager
    # Usage: darwin-rebuild switch --flake .
    darwinConfigurations = nixpkgs.lib.genAttrs darwinHosts (
      hostname:
        nix-darwin.lib.darwinSystem {
          specialArgs = {inherit inputs;};
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
            {
              home-manager = {
                useGlobalPkgs = true; # Use system nixpkgs instead of standalone
                useUserPackages = true; # Install to /etc/profiles instead of ~/.nix-profile
                extraSpecialArgs = {inherit inputs;};
                users.${username} = import ./home-manager;
              };
            }
          ];
        }
    );

    # NixOS configurations
    nixosConfigurations = {
      exp0 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
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
