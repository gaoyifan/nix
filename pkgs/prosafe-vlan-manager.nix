{pkgs}: let
  python = pkgs.python3.withPackages (pythonPackages:
    with pythonPackages; [
      beautifulsoup4
      click
      pydantic
      requests
    ]);
in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "prosafe-vlan-manager";
    version = "0-unstable-2026-08-27";

    src = pkgs.fetchFromGitHub {
      owner = "gaoyifan";
      repo = "prosafe-vlan-manager";
      rev = "0890b305e87938e7dfd06bc097155e6430d48d3d";
      hash = "sha256-oNW1H7rgY3PmfyWwau11rSv2TDllyFSDNOxYuHg3q80=";
    };

    nativeBuildInputs = [pkgs.makeWrapper];

    doCheck = true;
    checkPhase = ''
      ${python.interpreter} -m compileall -q prosafe
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/lib/prosafe-vlan-manager"
      cp -r prosafe "$out/lib/prosafe-vlan-manager/"
      makeWrapper ${python.interpreter} "$out/bin/prosafe-vlan-manager" \
        --add-flags "-m prosafe" \
        --prefix PYTHONPATH : "$out/lib/prosafe-vlan-manager"

      runHook postInstall
    '';

    meta = {
      description = "Declaratively manage VLANs on supported NETGEAR ProSAFE switches";
      homepage = "https://github.com/gaoyifan/prosafe-vlan-manager";
      license = pkgs.lib.licenses.agpl3Only;
      mainProgram = "prosafe-vlan-manager";
      platforms = pkgs.lib.platforms.linux;
    };
  }
