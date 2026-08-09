{
  self,
  forAllSystems,
  nixpkgs,
  cliApps,
  customPackages,
  pkgsFor,
  overlay,
  system-manager,
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
    }
    // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
      cjia-image = self.nixosConfigurations.cjia.config.system.build.sdImage;
      somo-nanopi-r4s-image = self.nixosConfigurations.somo-nanopi-r4s.config.system.build.sdImage;
    });

  apps = forAllSystems (system: cliApps.mkApps self.packages.${system});

  overlays.default = overlay;
}
