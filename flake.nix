{
  description = "Nix configuration for yifan";

  nixConfig = {
    extra-substituters = ["https://nix-cache.yfgao.net"];
    extra-trusted-public-keys = ["nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="];
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

    flake-utils.url = "github:numtide/flake-utils";

    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nix-darwin,
    flake-utils,
    ...
  }: let
    username = "yifan";

    # Custom packages for a system
    mkCustomPkgs = pkgs: import ./packages {inherit pkgs;};

    # Darwin hosts (all aarch64-darwin)
    darwinHosts = [
      "Yifans-MacBook-Air-2022"
      "Yifans-Mac-Studio"
      "default"
    ];

    # Helper function to create darwin configurations
    mkDarwinConfiguration = hostname: let
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
              extraSpecialArgs = {inherit customPkgs;};
              users.${username} = import ./home.nix;
            };
          }
        ];
      };
  in
    # Per-system outputs (devShells, legacyPackages for CI, homeConfigurations)
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      customPkgs = mkCustomPkgs pkgs;
    in {
      # Expose custom packages for CI/CD binary cache builds
      packages = customPkgs;

      # Standalone home-manager configuration (per-system)
      # Usage: home-manager switch --flake .#yifan
      legacyPackages.homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [./home.nix];
        extraSpecialArgs = {inherit customPkgs;};
      };

      # Devshell for the current system
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.nh
          pkgs.nix-output-monitor
          pkgs.git
          pkgs.alejandra
          pkgs.nil
          # Use home-manager from flake input for cross-platform compatibility
          home-manager.packages.${system}.default
        ];
      };
    })
    # Darwin configurations (generated from darwinHosts)
    // {
      darwinConfigurations = nixpkgs.lib.genAttrs darwinHosts mkDarwinConfiguration;
    };
}
