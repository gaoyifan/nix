{pkgs}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "codex-usage";
  version = "0-unstable-2026-08-30";

  src = ./codex-usage;
  strictDeps = true;
  dontBuild = true;

  nativeBuildInputs = [pkgs.makeWrapper];
  nativeCheckInputs = [pkgs.python3];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${pkgs.python3.interpreter} -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 codex_usage.py "$out/libexec/codex-usage.py"
    makeWrapper ${pkgs.python3.interpreter} "$out/bin/codex-usage" \
      --add-flags "$out/libexec/codex-usage.py"
    runHook postInstall
  '';

  meta = {
    description = "Summarize recent Codex token usage and its USD equivalent";
    mainProgram = "codex-usage";
    platforms = pkgs.lib.platforms.all;
  };
}
