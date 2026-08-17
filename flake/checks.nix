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
    lowMemoryGptHost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [inputs.disko.nixosModules.disko ../nixos/tests/low-memory-gpt-host.nix];
    };
  in
    nixpkgs.lib.recursiveUpdate deployChecks {
      x86_64-linux = {
        home-router = x86Pkgs.testers.runNixOSTest (import ../nixos/tests/home-router.nix {inherit inputs;});
        low-memory-disk-image = import ../nixos/tests/low-memory-disk-image.nix {
          inherit (inputs) disko;
          hostConfig = lowMemoryGptHost;
          inherit (self.lib) mkNixosDiskImage;
          inherit nixpkgs;
          pkgs = x86Pkgs;
        };
        nixos-disk-image-google = self.packages.x86_64-linux.nixos-disk-image-google;
        nixos-disk-writer-kexec = import ../nixos/tests/nixos-disk-writer-kexec.nix {
          hostConfig = lowMemoryGptHost;
          kexecInstallerTarball = self.packages.x86_64-linux.nixos-disk-writer-kexec;
          inherit (self.lib) mkNixosDiskImage;
          pkgs = x86Pkgs;
        };
        oob-ssh = x86Pkgs.testers.runNixOSTest (import ../nixos/tests/oob-ssh.nix {pkgs = x86Pkgs;});
      };
    };
}
