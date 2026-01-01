{
  description = "Nix configuration for yifan";

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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

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
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      ...
    }@inputs:
    let
      # Supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Helper to generate per-system attributes
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Default username
      username = "yifan";

      # Darwin hosts (all aarch64-darwin)
      darwinHosts = [
        "Yifans-MacBook-Air-2022"
        "Yifans-Mac-Studio"
        "default"
      ];
    in
    {
      # Custom packages
      # Accessible through 'nix build .#lazyssh'
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});

      # Formatter for nix files, available through 'nix fmt'
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      # Overlays for custom packages
      overlays = import ./overlays { inherit inputs; };

      # Devshell for each system
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = import ./shell.nix {
            inherit pkgs home-manager nix-darwin;
          };
        }
      );

      # Standalone home-manager configuration
      # Usage: home-manager switch --flake .#yifan
      legacyPackages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              self.overlays.additions
              self.overlays.modifications
            ];
            config.allowUnfree = true;
          };
        in
        {
          homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = { inherit inputs; };
            modules = [ ./home-manager/home.nix ];
          };
        }
      );

      # Darwin configurations
      # Usage: darwin-rebuild switch --flake .#hostname
      darwinConfigurations = nixpkgs.lib.genAttrs darwinHosts (
        hostname:
        let
          system = "aarch64-darwin";
        in
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            # Apply overlays at the nixpkgs level
            {
              nixpkgs.overlays = [
                self.overlays.additions
                self.overlays.modifications
              ];
              nixpkgs.config.allowUnfree = true;
            }

            ./darwin/configuration.nix

            # Home Manager module
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs; };
                users.${username} = import ./home-manager/home.nix;
              };
            }
          ];
        }
      );
    };
}
