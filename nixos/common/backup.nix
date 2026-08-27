{
  config,
  lib,
  username,
  ...
}: let
  cfg = config.services.resticBackup;
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

  config.services.restic.backups.system = {
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
