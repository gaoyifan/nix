{
  forAllLinuxSystems,
  username,
  nixpkgs,
  overlay,
  system-manager,
  ...
}: let
  resticBackupHosts = [
    "bitmagnet-db2"
    "debian41"
    "debian20"
    "debian22"
    "misc0-61"
    "misc0-sz"
    "oracle"
  ];
  tailscaleUserspaceHosts = [
    "debian20"
    "debian22"
    "debian40"
    "debian41"
    "debian42"
  ];
  systemManagerHosts = nixpkgs.lib.unique (resticBackupHosts ++ tailscaleUserspaceHosts);
  internalSubstitutersFor = hostname:
    import ../secrets/internal-substituters.nix {
      hostname = builtins.head (nixpkgs.lib.splitString "." hostname);
    };
  mkSystemConfig = system: hostname: extraModules:
    system-manager.lib.makeSystemConfig {
      overlays = [overlay];
      specialArgs = {
        inherit username;
        internalSubstituters = internalSubstitutersFor hostname;
      };
      modules =
        [
          ../system-manager/nix.nix
          ../system-manager/restic.nix
          ../system-manager/tailscale.nix
          # system-manager imports NixOS nginx without the full NixOS module list.
          "${nixpkgs}/nixos/modules/security/dhparams.nix"
          ({pkgs, ...}: {
            nixpkgs.hostPlatform = system;
            nixpkgs.config.allowUnfree = true;
            environment.systemPackages = [pkgs.tsshd];
          })
        ]
        ++ extraModules;
    };
in {
  systemConfigs = forAllLinuxSystems (
    system:
      {
        default = mkSystemConfig system "default" [];
      }
      // nixpkgs.lib.genAttrs systemManagerHosts (
        host:
          mkSystemConfig system host (
            nixpkgs.lib.optional (builtins.elem host resticBackupHosts) {
              services.resticBackup.enable = true;
            }
            ++ nixpkgs.lib.optional (builtins.elem host tailscaleUserspaceHosts) {
              services.tailscale.interfaceName = "userspace-networking";
            }
          )
      )
  );
}
