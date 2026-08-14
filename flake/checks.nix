{
  self,
  inputs,
  nixpkgs,
  pkgsFor,
  overlay,
  deploy-rs,
  ...
}: {
  checks = let
    # Hermes reads filtered package sources during evaluation, but
    # `nix flake check --no-build` cannot materialize them in a read-only store.
    # Keep the real deployment path intact and replace only the check profile.
    deployForChecks =
      nixpkgs.lib.updateManyAttrsByPath [
        {
          path = ["nodes" "somo-minisforum" "profiles" "system" "path"];
          update = _: deploy-rs.lib.x86_64-linux.activate.noop (pkgsFor "x86_64-linux").emptyDirectory;
        }
      ]
      self.deploy;
    deployChecks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks deployForChecks) deploy-rs.lib;
    x86Pkgs = (pkgsFor "x86_64-linux").extend overlay;
  in
    nixpkgs.lib.recursiveUpdate deployChecks {
      x86_64-linux = {
        home-router = x86Pkgs.testers.runNixOSTest (import ../nixos/tests/home-router.nix {inherit inputs;});
        oob-ssh = x86Pkgs.testers.runNixOSTest (import ../nixos/tests/oob-ssh.nix {pkgs = x86Pkgs;});
      };
    };
}
