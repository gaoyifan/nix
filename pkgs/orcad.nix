{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
}: let
  assets = {
    x86_64-linux = {
      arch = "x64";
      hash = "sha256-zAvkIbbcmV50yFXbIdf2xCjtdZQZ1qSUyK0IdzgS6ik=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-C/7AVaKAOBrnP8rFeK1dM+Rv+4mFbpQTNasRhpLxn0g=";
    };
  };
  asset = assets.${stdenv.hostPlatform.system};
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "orcad";
    version = "1.4.277";
    src = fetchurl {
      url = "https://github.com/stablyai/orca/releases/download/v${finalAttrs.version}/orca-server-linux-${asset.arch}.tar.gz";
      inherit (asset) hash;
    };

    nativeBuildInputs = [makeWrapper];
    dontBuild = true;
    # The launcher and daemon use upstream's byte-level bundle and Node identities.
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      bundle="$out/lib/orca-server"
      mkdir -p "$bundle"
      cp -r . "$bundle/"
      makeWrapper "$bundle"/runtimes/node-*/bin/node "$out/bin/orcad" \
        --add-flags "$bundle/orcad/orcad.js" \
        --set ORCA_VERSION ${finalAttrs.version}
      runHook postInstall
    '';

    meta = {
      description = "Orca headless coding-agent runtime";
      homepage = "https://github.com/stablyai/orca";
      license = lib.licenses.mit;
      mainProgram = "orcad";
      platforms = builtins.attrNames assets;
    };
  })
