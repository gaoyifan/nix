{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_12,
  pnpmConfigHook,
  nodejs-slim,
  python3,
  autoPatchelfHook,
  makeBinaryWrapper,
}:
stdenv.mkDerivation (finalAttrs: let
  target =
    if stdenv.hostPlatform.isAarch64
    then "linux-arm64-glibc"
    else "linux-x64-glibc";
in {
  pname = "orcad";
  version = "1.4.240";

  # Keep dependency sources out of fetchPnpmDeps' JSON metadata fixup.
  ORCA_PNPM_GLOBAL_VIRTUAL_STORE = "0";

  src = fetchFromGitHub {
    owner = "stablyai";
    repo = "orca";
    tag = "v${finalAttrs.version}";
    # Keep the commit for Orcad's official skills, but exclude Git pack bytes
    # from the fixed-output hash: their compression can change upstream.
    leaveDotGit = true;
    postFetch = ''
      git -C "$out" rev-parse HEAD > "$out/.source-commit"
      rm -r "$out/.git"
    '';
    hash = "sha256-IpcYuDVePAFR7hgZZy4b7mIvnayjNwzbPoVOPbiGyv4=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname src ORCA_PNPM_GLOBAL_VIRTUAL_STORE;
    pnpm = pnpm_12;
    fetcherVersion = 4;
    postInstall = ''
      # The mobile web bundle uses a separate workspace and lockfile.
      pnpm --dir mobile install --store-dir "$storePath" --force --ignore-scripts --frozen-lockfile
      node --input-type=module <<'JS'
      import { materializeWatcherPackage } from './config/scripts/orcad-watcher-package.mjs';
      await materializeWatcherPackage('linux-x64-glibc');
      await materializeWatcherPackage('linux-arm64-glibc');
      JS
      cp -r out/.orcad-watchers "$out/orcad-watchers"
    '';
    hash = "sha256-gaeLQzgbf/LKVtpbMhf/yfQ8bvYoK6Xa/5LPKM5ihOM=";
  };

  nativeBuildInputs = [
    nodejs-slim
    python3
    pnpm_12
    pnpmConfigHook
    autoPatchelfHook
    makeBinaryWrapper
  ];
  buildInputs = [stdenv.cc.cc.lib];

  postPatch = ''
    substituteInPlace config/scripts/build-source-commit.mjs \
      --replace-fail "execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim()" "'$(cat .source-commit)'"

    # Build against Nix's Node headers and libraries instead of downloading a
    # runtime or enforcing the portable release's Ubuntu library versions.
    substituteInPlace config/scripts/build-orcad-prebuilds.mjs \
      --replace-fail "await preparePinnedNodeDir({ target: slot, workDir: join(workDir, 'nodedir') })" "'${nodejs-slim}'" \
      --replace-fail 'glibcFloor: slotGlibcFloor(slot)' 'glibcFloor: { label: "Nix store libraries", families: [] }'
    substituteInPlace config/scripts/build-orcad-node.mjs \
      --replace-fail 'await ensurePinnedNodeExecutable({ target })' "'${lib.getExe nodejs-slim}'"

    # The runtime marker and startup handoff must identify the actual Nix Node.
    node --input-type=module <<'JS'
    import { createHash } from 'node:crypto';
    import { readFileSync, writeFileSync } from 'node:fs';
    import { NODE_RUNTIME_ASSETS, NODE_RUNTIME_PIN } from './src/shared/node-runtime-pin.ts';
    const path = 'src/shared/node-runtime-pin.ts';
    const hash = createHash('sha256').update(readFileSync(process.execPath)).digest('hex');
    writeFileSync(path, readFileSync(path, 'utf8')
      .replace("version: '" + NODE_RUNTIME_PIN.version + "'", "version: '" + process.versions.node + "'")
      .replace("executableSha256: '" + NODE_RUNTIME_ASSETS['${target}'].executableSha256 + "'", "executableSha256: '" + hash + "'"));
    JS
  '';

  buildPhase = ''
    runHook preBuild
    pnpmRoot=mobile pnpmConfigHook
    pnpm --dir mobile run postinstall
    pnpm run build:mobile-web
    cp -r --no-preserve=mode ${finalAttrs.pnpmDeps}/orcad-watchers out/.orcad-watchers
    pnpm run build:orcad --target ${target}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib"
    mv out/orcad out/runtimes "$out/lib/"
    runtime_hash=$(cat "$out/lib/orcad/.runtime-node")
    ln -sf ${lib.getExe nodejs-slim} "$out/lib/runtimes/node-$runtime_hash/bin/node"
    makeWrapper ${lib.getExe nodejs-slim} "$out/bin/orcad" \
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
    node -e 'process.stdout.write(require("./preflight.json").artifactVersion)' > "$out/lib/orcad/.version"
  '';

  meta = {
    description = "Orca headless coding-agent runtime";
    homepage = "https://github.com/stablyai/orca";
    license = lib.licenses.mit;
    mainProgram = "orcad";
    platforms = ["x86_64-linux" "aarch64-linux"];
  };
})
