{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.services.mutagen.dotfileSync.enable {
    # Remove this migration after every managed host has switched from the old
    # `.codex/skills` file entry to the `.codex/skills/custom` child entry.
    home.file.".codex/skills/custom".force = true;

    home.activation.migrateCodexSkills = lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] ''
      target="$HOME/.codex/skills"

      if [ -L "$target" ]; then
        old_target="$(readlink "$target")"
        store_dir=${lib.escapeShellArg builtins.storeDir}

        case "$old_target" in
          "$store_dir"/*-home-manager-files/.codex/skills)
            run rm "$target"
            ;;
        esac
      fi
    '';
  };
}
