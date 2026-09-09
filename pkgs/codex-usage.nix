{pkgs}:
pkgs.rustPlatform.buildRustPackage {
  pname = "codex-usage";
  version = "2.0.0";

  src = ./codex-usage;
  strictDeps = true;

  cargoLock.lockFile = ./codex-usage/Cargo.lock;

  meta = {
    description = "Summarize recent Codex token usage and its USD equivalent";
    mainProgram = "codex-usage";
    platforms = pkgs.lib.platforms.all;
  };
}
