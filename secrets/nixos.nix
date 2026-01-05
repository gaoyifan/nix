# NixOS host secrets configuration
{
  config,
  lib,
  ...
}: let
  cfg = config.services.secrets;
in {
  options.services.secrets.nixos = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
      options = {
        pppoe = {
          peerFile = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.filesDir}/nixos/${name}/ppp-peer-isp";
            description = "PPP peer configuration file";
          };
          chapSecretsFile = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.filesDir}/nixos/${name}/chap-secrets";
            description = "PPP CHAP secrets file";
          };
          papSecretsFile = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.filesDir}/nixos/${name}/pap-secrets";
            description = "PPP PAP secrets file";
          };
        };

        wireguard = {
          privateKeyFile = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.filesDir}/nixos/${name}/wg-private-key";
            description = "WireGuard private key file";
          };
        };

        tailscale = {
          authKeyFile = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.filesDir}/nixos/${name}/tailscale-auth-key";
            description = "Tailscale auth key file";
          };
        };
      };
    }));
    default = {};
    description = "Per-host NixOS secrets configuration";
  };
}
