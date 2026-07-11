# Secrets configuration - base module for NixOS
# This module only defines the filesDir option.
# home-manager imports secrets/home.nix directly for home-manager-specific secrets.
{
  config,
  lib,
  ...
}: let
  hasRealSecrets = builtins.pathExists ./files/.gitkeep;
  secretsDir =
    if hasRealSecrets
    then ./files
    else ./files-example;
in {
  options.services.secrets = {
    filesDir = lib.mkOption {
      type = lib.types.path;
      default = secretsDir;
      description = "Path to the directory containing secret files (real or example)";
      internal = true;
    };

    nixos."somo-minisforum".vms = lib.mkOption {
      type = lib.types.attrs;
      default = import (secretsDir + "/nixos/somo-minisforum/vms.nix") {
        hermes = config.services.secrets.nixos.hermes;
      };
      description = "Declarative Incus VM definitions for somo-minisforum.";
      internal = true;
    };

    nixos.hermes = lib.mkOption {
      type = lib.types.attrs;
      default = import (secretsDir + "/nixos/hermes.nix");
      description = "Hermes operator VM inventory shared by SOMO services.";
      internal = true;
    };

    nixos.internalSubstituters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        (import (secretsDir + "/nixos/internal-substituters.nix") {
          hostname = config.networking.hostName;
        }).substituters;
      description = "Internal-only Nix substituters enabled for this host.";
      internal = true;
    };

    nixos."somo-minisforum".wgEl2 = lib.mkOption {
      type = lib.types.attrs;
      default =
        import (secretsDir + "/nixos/somo-minisforum/wg-el2.nix")
        // {
          privateKeyFile = "${config.services.secrets.filesDir}/nixos/somo-minisforum/wg-el2-private-key";
        };
      description = "WireGuard EL2 egress configuration for somo-minisforum.";
      internal = true;
    };

    nixos."somo-gw".caddy = lib.mkOption {
      type = lib.types.attrs;
      default = import (secretsDir + "/nixos/somo-gw/caddy.nix") {
        hermes = config.services.secrets.nixos.hermes;
      };
      description = "Caddy virtual hosts and private DNS delegates for somo-gw.";
      internal = true;
    };

    nixos.wlt.sshHostKeyFile = lib.mkOption {
      type = lib.types.path;
      default = secretsDir + "/nixos/wlt-ssh-host-key";
      description = "Shared SSH host private key for the WLT selector service.";
      internal = true;
    };

    nixos.internalCa = {
      certFile = lib.mkOption {
        type = lib.types.path;
        default = secretsDir + "/nixos/internal-ca.pem";
        description = "Internal CA certificate.";
        internal = true;
      };
      keyFile = lib.mkOption {
        type = lib.types.path;
        default = secretsDir + "/nixos/internal-ca-key.pem";
        description = "Internal CA private key.";
        internal = true;
      };
    };

    nixos.wlt.tls = {
      certFile = lib.mkOption {
        type = lib.types.path;
        default = secretsDir + "/nixos/wlt-server.pem";
        description = "WLT HTTPS server certificate signed by the internal CA.";
        internal = true;
      };
      keyFile = lib.mkOption {
        type = lib.types.path;
        default = secretsDir + "/nixos/wlt-server-key.pem";
        description = "WLT HTTPS server private key.";
        internal = true;
      };
    };
  };
}
