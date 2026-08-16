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
    nixosBootstrapImages =
      nixpkgs.lib.mapAttrs' (
        name: host:
          nixpkgs.lib.nameValuePair
          "nixos-bootstrap-image-${name}"
          (self.lib.mkNixosBootstrap {inherit host;})
      ) (
        nixpkgs.lib.filterAttrs (
          _: host:
            host.pkgs.stdenv.hostPlatform.system
            == system
            && (host.config.disko.devices.disk or {}) != {}
        )
        self.nixosConfigurations
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
      nixos-disk-writer-kexec =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs.nixosImages = inputs.nixos-images;
          modules = [
            inputs.nixos-images.nixosModules.kexec-installer
            inputs.nixos-images.nixosModules.noninteractive
            ../nixos/nixos-disk-writer-kexec.nix
          ];
        }).config.system.build.kexecInstallerTarball;
    }
    // nixosBootstrapImages
    // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
      nanopi-r4s-bootstrap-image = self.nixosConfigurations.nanopi-r4s-bootstrap.config.system.build.sdImage;
    });

  apps = forAllSystems (system: cliApps.mkApps self.packages.${system});

  overlays.default = overlay;
}
