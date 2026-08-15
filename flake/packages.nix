{
  self,
  forAllSystems,
  nixpkgs,
  cliApps,
  customPackages,
  pkgsFor,
  overlay,
  system-manager,
  inputs,
  ...
}: {
  packages = forAllSystems (system: let
    pkgs = pkgsFor system;
    nixosProfiles = nixpkgs.lib.attrValues (
      nixpkgs.lib.filterAttrs (_: node: node.profiles.system.path.system == system) self.deploy.nodes
    );
  in
    (cliApps.mkPackages {
      inherit pkgs;
      customPackages = customPackages pkgs;
    })
    // nixpkgs.lib.optionalAttrs (!(nixpkgs.lib.hasSuffix "darwin" system)) {
      system-manager = system-manager.packages.${system}.default;
      nixos-hosts-cache = pkgs.releaseTools.aggregate {
        name = "nixos-hosts-cache";
        constituents = map (node: node.profiles.system.path) nixosProfiles;
      };
      nixos-anywhere-tiny-kexec =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs.nixosImages = inputs.nixos-images;
          modules = [
            inputs.nixos-images.nixosModules.kexec-installer
            inputs.nixos-images.nixosModules.noninteractive
            ../nixos/nixos-anywhere-kexec.nix
          ];
        }).config.system.build.kexecInstallerTarball;
    }
    // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
      nanopi-r4s-bootstrap-image = self.nixosConfigurations.nanopi-r4s-bootstrap.config.system.build.sdImage;
    });

  apps = forAllSystems (system: cliApps.mkApps self.packages.${system});

  overlays.default = overlay;
}
