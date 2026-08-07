{
  forAllSystems,
  nixpkgsForSystem,
  ...
}: {
  formatter = forAllSystems (system: (nixpkgsForSystem system).legacyPackages.${system}.alejandra);
}
