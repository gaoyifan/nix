{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_12,
  pnpmConfigHook,
  nodejs,
  orcad-bun,
  autoPatchelfHook,
  makeBinaryWrapper,
  jq,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "orcad";
  version = "1.4.216";

  src = fetchFromGitHub {
    owner = "stablyai";
    repo = "orca";
    tag = "v${finalAttrs.version}";
    hash = "sha256-lh1IjgrJiHD1Iz3rT86e65KBZwDr6jy8ZsItIS6QKxI=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname src;
    pnpm = pnpm_12;
    fetcherVersion = 4;
    postInstall = ''
      node --input-type=module <<'JS'
      import { materializeWatcherPackage } from './config/scripts/orcad-watcher-package.mjs';
      await materializeWatcherPackage('linux-x64-glibc');
      JS
      cp -r out/.orcad-watchers "$out/orcad-watchers"
    '';
    hash = "sha256-SgksTMSxMbkMlefllGTFyUkuS5hZTtZO0A6BMrzdKLI=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_12
    pnpmConfigHook
    autoPatchelfHook
    makeBinaryWrapper
    jq
  ];
  buildInputs = [stdenv.cc.cc.lib];

  buildPhase = ''
    runHook preBuild
    mkdir -p out
    cp -r --no-preserve=mode ${finalAttrs.pnpmDeps}/orcad-watchers out/.orcad-watchers
    ORCAD_BUILD_TARGET=linux-x64-glibc \
      ORCAD_BUILD_TARGET_IS_CURRENT=1 \
      ORCAD_BUN_RUNTIME_PATH=${lib.getExe orcad-bun} \
      LD_LIBRARY_PATH=${lib.makeLibraryPath [stdenv.cc.cc.lib]} \
      node config/scripts/build-orcad.mjs
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib"
    mv out/orcad "$out/lib/"
    ln -sf ${lib.getExe orcad-bun} "$out/lib/orcad/bun-runtime"
    makeWrapper ${lib.getExe orcad-bun} "$out/bin/orcad" \
      --add-flags "$out/lib/orcad/orcad.js" \
      --set ORCA_VERSION ${finalAttrs.version} \
      --set ORCA_APP_VERSION ${finalAttrs.version}
    runHook postInstall
  '';

  # ELF fixups change the bytes covered by upstream's startup identity check.
  postPhases = ["finalizeRuntimePhase"];
  finalizeRuntimePhase = ''
    "$out/bin/orcad" --orcad-profile-state-preflight \
      00000000-0000-4000-8000-000000000000 > preflight.json
    jq -er .artifactVersion preflight.json > "$out/lib/orcad/.version"
  '';

  meta = {
    description = "Orca headless coding-agent runtime";
    homepage = "https://github.com/stablyai/orca";
    license = lib.licenses.mit;
    mainProgram = "orcad";
    platforms = ["x86_64-linux"];
  };
})
