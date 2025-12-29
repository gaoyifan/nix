{
  description = "Home Manager configuration of yifan";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      # Detect architecture and kernel dynamically (Impure)
      system = builtins.currentSystem;
      pkgs = nixpkgs.legacyPackages.${system};

      username = "yifan";

      # Helper flags
      isLinux = pkgs.stdenv.isLinux;
      isDarwin = pkgs.stdenv.isDarwin;
    in
    {
      homeConfigurations."${username}" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home.nix
          # Conditionally include modules based on Kernel (create these files if you want to split config)
          # (if isLinux then ./linux-specific.nix else {})
          # (if isDarwin then ./macos-specific.nix else {})
        ];
        extraSpecialArgs = { inherit system isLinux isDarwin; };
      };

      # Devshell for the current system
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nh
          nix-output-monitor
          pkgs.home-manager
          git
          nixfmt
          nixd
        ];
      };
    };
}
