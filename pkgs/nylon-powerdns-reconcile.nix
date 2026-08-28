{pkgs}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "nylon-powerdns-reconcile";
  version = "0-unstable-2026-08-28";

  src = ./nylon-powerdns-reconcile;
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
    install -Dm755 nylon_powerdns_reconcile.py \
      "$out/libexec/nylon-powerdns-reconcile.py"
    makeWrapper ${pkgs.python3.interpreter} "$out/bin/nylon-powerdns-reconcile" \
      --add-flags "$out/libexec/nylon-powerdns-reconcile.py"
    runHook postInstall
  '';

  meta = {
    description = "Plan and safely apply Nylon A/AAAA snapshots to PowerDNS";
    mainProgram = "nylon-powerdns-reconcile";
    platforms = pkgs.lib.platforms.all;
  };
}
