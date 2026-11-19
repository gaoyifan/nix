{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
}: let
  assets = {
    x86_64-linux = {
      arch = "x64";
      hash = "sha256-j3i1rLXlelOqkFjtxwGvTZ5LQaDK8/d/jOI8Lhu+ytY=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-U7l1QX8oX/VSamPW2QwcN+jBGYojrFtdYT4efCFrjkw=";
    };
  };
  asset = assets.${stdenv.hostPlatform.system};
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "orcad";
    version = "1.4.264";
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
      mkdir -p "$out/lib/orca-server"
      cp -r . "$out/lib/orca-server/"
      makeWrapper "$out/lib/orca-server/bin/orca-ide" "$out/bin/orca-ide" \
        --set NIX_LD ${stdenv.cc.bintools.dynamicLinker} \
        --set NIX_LD_LIBRARY_PATH ${lib.makeLibraryPath [stdenv.cc.libc stdenv.cc.cc.lib]}
      makeWrapper "$out/bin/orca-ide" "$out/bin/orcad" \
        --add-flags 'serve --bind 127.0.0.1'
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
