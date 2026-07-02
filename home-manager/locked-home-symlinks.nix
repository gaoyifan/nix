{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.lockedHomeSymlinks;

  applyFlag = flag: ''
    locked_home_symlinks_apply_flag() {
      target="$1"

      if [ -e "$target" ] || [ -L "$target" ]; then
        run /usr/bin/find "$target" -type l -exec /usr/bin/chflags -h ${flag} {} +
      fi
    }

    ${lib.concatMapStrings (path: ''
        locked_home_symlinks_apply_flag "$HOME"/${lib.escapeShellArg path}
      '')
      cfg.paths}

    unset -f locked_home_symlinks_apply_flag
  '';
in {
  options.services.lockedHomeSymlinks = {
    enable = lib.mkEnableOption "locking selected Home Manager symlinks with macOS immutable file flags";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["Library/Rime"];
      description = ''
        Home-relative paths whose symbolic links should be made user-immutable
        recursively during activation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "services.lockedHomeSymlinks uses macOS chflags and is only supported on Darwin.";
      }
      {
        assertion = cfg.paths != [];
        message = "services.lockedHomeSymlinks.paths must contain at least one path.";
      }
    ];

    home.activation.unlockLockedHomeSymlinks =
      lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] (applyFlag "nouchg");

    home.activation.lockLockedHomeSymlinks =
      lib.hm.dag.entryAfter ["linkGeneration"] (applyFlag "uchg");
  };
}
