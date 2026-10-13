# Share ~/.agents/skills with Claude Code.
# Claude Code only discovers ~/.claude/skills/<name>/, so flatten the
# ~/.agents/skills/<author>/<name>/ layout into per-skill symlinks.
{lib, ...}: {
  home.activation.linkClaudeSkills = lib.hm.dag.entryAfter ["linkGeneration"] ''
    src="$HOME/.agents/skills"
    dst="$HOME/.claude/skills"

    run mkdir -p "$dst"
    run find "$dst" -maxdepth 1 -type l -lname "$src/*" -delete
    for skill_md in "$src"/*/*/SKILL.md; do
      [ -f "$skill_md" ] || continue
      skill="''${skill_md%/SKILL.md}"
      if [ -e "$dst/''${skill##*/}" ]; then
        warnEcho "Skipping $skill: $dst/''${skill##*/} already exists"
      else
        run ln -s "$skill" "$dst/''${skill##*/}"
      fi
    done
  '';
}
