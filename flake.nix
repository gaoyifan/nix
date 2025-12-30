{
  description = "Home Manager configuration of yifan";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      username = "yifan";

      # Helper flags
      isLinux = pkgs.stdenv.isLinux;
      isDarwin = pkgs.stdenv.isDarwin;

      # Custom packages
      customPkgs = {
        lazyssh = import ./packages/lazyssh.nix {inherit pkgs;};
      };
    in {
      legacyPackages.homeConfigurations."${username}" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home.nix
        ];
        extraSpecialArgs = {inherit system isLinux isDarwin customPkgs;};
      };

      # Devshell for the current system
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          nh
          nix-output-monitor
          pkgs.home-manager
          git
          alejandra
          nil
        ];
      };
    });
}
