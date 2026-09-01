{
  config,
  lib,
  options,
  username,
  ...
}: let
  cfg = config.services.resticBackup;
  hasOption = path: lib.hasAttrByPath path options;
  homeRouterEnabled =
    hasOption ["networking" "homeRouter" "enable"]
    && config.networking.homeRouter.enable;
  incusVmsEnabled =
    hasOption ["virtualisation" "incusVms" "enable"]
    && config.virtualisation.incusVms.enable;
  oobSshEnabled =
    hasOption ["services" "oobSsh" "enable"]
    && config.services.oobSsh.enable;
  automaticPaths =
    lib.optionals homeRouterEnabled [
      "/var/lib/dnsmasq"
      "/var/lib/wlt/persist"
    ]
    ++ lib.optional oobSshEnabled "/var/lib/oob-ssh";
in {
  options.services.resticBackup = {
    extraPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional paths to include in the system backup.";
    };

    extraExcludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional exclusion patterns appended in the specified order.";
    };
  };

  config = lib.mkMerge [
    {
      services.restic.backups.system = {
        environmentFile = "/home/${username}/.config/restic/env";
        paths = lib.sort builtins.lessThan (
          [
            "/etc"
            "/home"
            "/opt"
            "/root"
            "/srv"
            "/var/lib/tailscale"
          ]
          ++ automaticPaths
          ++ cfg.extraPaths
        );
        exclude =
          [
            ".antigravity-server"
            ".bun"
            ".cache"
            ".cursor-server"
            ".npm"
            ".rustup"
            ".venv"
            "/home/linuxbrew"
            "/home/${username}/.cargo/registry"
            "/home/${username}/.local"
            "/home/${username}/.syncd-dotfiles"
            "/home/${username}/Sync"
            "/home/${username}/go/pkg/mod"
            "/home/${username}/nix"
            "/home/${username}/src"
            "/home/${username}/tmp"
            "__pycache__"
            "cache"
            "log"
            "node_modules"
            "target"
          ]
          ++ cfg.extraExcludes;
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };
    }

    (lib.mkIf incusVmsEnabled {
      services.restic.backups.incus-state = {
        environmentFile = "/home/${username}/.config/restic/env";
        paths = ["/var/lib/incus"];
        extraBackupArgs = ["--one-file-system"];
        timerConfig = {
          OnCalendar = "*-*-* 02:00:00";
          RandomizedDelaySec = "30m";
          Persistent = true;
        };
      };
    })
  ];
}
