{
  pkgs,
  codex,
}:
pkgs.writeShellScriptBin "codex-reindex" ''
  export CODEX_REINDEX_CODEX=${pkgs.lib.escapeShellArg (pkgs.lib.getExe codex)}
  exec ${pkgs.lib.getExe pkgs.uv} run --script ${./codex-reindex/codex_reindex.py} "$@"
''
