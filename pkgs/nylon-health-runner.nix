{pkgs}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "nylon-health-runner";
  version = "0-unstable-2026-08-28";

  src = ./nylon-health-runner;
  strictDeps = true;
  dontBuild = true;

  nativeBuildInputs = [pkgs.makeWrapper];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${pkgs.python3.interpreter} -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 nylon_health.py "$out/libexec/nylon-health.py"
    makeWrapper ${pkgs.python3.interpreter} "$out/bin/nylon-health" \
      --add-flags "$out/libexec/nylon-health.py" \
      --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.iproute2 pkgs.openssh]}
    runHook postInstall
  '';

  meta = {
    description = "Manifest-driven health checks for a Nylon mesh";
    mainProgram = "nylon-health";
    platforms = pkgs.lib.platforms.linux;
  };
}
