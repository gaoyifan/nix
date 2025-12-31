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

    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nix-darwin,
      ...
    }:
    let
      # Supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      username = "yifan";

      # Helper to generate per-system attributes
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Custom packages for a system
      mkCustomPkgs = pkgs: import ./packages { inherit pkgs; };

      # Darwin hosts (all aarch64-darwin)
      darwinHosts = [
        "Yifans-MacBook-Air-2022"
        "Yifans-Mac-Studio"
        "default"
      ];

      # Helper function to create darwin configurations
      mkDarwinConfiguration =
        hostname:
        let
          system = "aarch64-darwin";
          pkgs = nixpkgs.legacyPackages.${system};
          customPkgs = mkCustomPkgs pkgs;
        in
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inherit username customPkgs;
          };
          modules = [
            ./hosts/darwin.nix

            # Home Manager module
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit customPkgs; };
                users.${username} = import ./home.nix;
              };
            }
          ];
        };
    in
    {
      # Expose custom packages for CI/CD binary cache builds
      packages = forAllSystems (pkgs: mkCustomPkgs pkgs);

      # Standalone home-manager configuration (per-system)
      # Usage: home-manager switch --flake .#yifan
      legacyPackages = forAllSystems (pkgs: {
        homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [ ./home.nix ];
          extraSpecialArgs = {
            customPkgs = mkCustomPkgs pkgs;
          };
        };
      });

      # Devshell for each system
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nh
            pkgs.nix-output-monitor
            pkgs.git
            pkgs.alejandra
            pkgs.nil
            # Use home-manager from flake input for cross-platform compatibility
            home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        };
      });

      # Darwin configurations (generated from darwinHosts)
      darwinConfigurations = nixpkgs.lib.genAttrs darwinHosts mkDarwinConfiguration;
    };
}
