{pkgs}: let
  inherit (pkgs) lib;
  nodejs = pkgs.nodejs_24;
  pnpm = pkgs.stdenvNoCC.mkDerivation {
    pname = "pnpm";
    version = "12.0.0";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@pnpm/exe.linux-x64/-/exe.linux-x64-12.0.0.tgz";
      hash = "sha256-0MZO+rOdVg7zrk3Ivl3QiVHlQJ7S1Ty2uDF7dxPCYzM=";
    };
    nativeBuildInputs = [pkgs.autoPatchelfHook];
    buildInputs = [pkgs.stdenv.cc.cc.lib];
    installPhase = ''
      install -Dm755 pnpm "$out/bin/pnpm"
    '';
    passthru.nodejs-slim = nodejs;
  };
in
  pkgs.stdenv.mkDerivation (finalAttrs: {
    pname = "orcad";
    version = "1.4.214";

    src = pkgs.fetchFromGitHub {
      owner = "stablyai";
      repo = "orca";
      tag = "v${finalAttrs.version}";
      hash = "sha256-AhE9Ehl3iixVeI5o8Iu4Mq5vgtjjdITXmquKOAwRvHA=";
    };

    pnpmDeps = pkgs.fetchPnpmDeps {
      inherit (finalAttrs) pname src;
      inherit pnpm;
      fetcherVersion = 4;
      # pnpm 12 treats the fetcher's empty --registry as an empty base URL.
      prePnpmInstall = ''export NIX_NPM_REGISTRY=https://registry.npmjs.org'';
      nativeBuildInputs = [nodejs pkgs.curl pkgs.unzip];
      # Prefetch the runtime assets using this release's own pins and downloader.
      # nix-update refreshes this hash along with the source and npm dependencies.
      postInstall = ''
        node --input-type=module <<'JS'
        import { writeFileSync } from 'node:fs';
        import { ORCAD_BUN_RELEASE_ASSETS, orcadBunReleaseUrl } from './src/shared/orcad-bun-runtime.ts';
        import { materializeWatcherPackage } from './config/scripts/orcad-watcher-package.mjs';
        const asset = ORCAD_BUN_RELEASE_ASSETS['linux-x64-glibc'];
        writeFileSync('bun-asset.json', JSON.stringify({ ...asset, url: orcadBunReleaseUrl(asset) }));
        await materializeWatcherPackage('linux-x64-glibc');
        JS
        curl --fail --location "$(jq -r .url bun-asset.json)" --output bun.zip
        echo "$(jq -r .sha256 bun-asset.json)  bun.zip" | sha256sum --check
        unzip -p bun.zip '*/bun' > "$out/bun-runtime"
        echo "$(jq -r .executableSha256 bun-asset.json)  $out/bun-runtime" | sha256sum --check
        cp -r out/.orcad-watchers "$out/orcad-watchers"
      '';
      hash = "sha256-ptTJ10Lhgy6ZETFRFhATt7mcr85N/TAwemuA+GbeoAA=";
    };

    nativeBuildInputs = [
      nodejs
      pnpm
      pkgs.pnpmConfigHook
      pkgs.python3
      pkgs.jq
      pkgs.patchelf
      pkgs.makeBinaryWrapper
      (pkgs.node-gyp.override {inherit nodejs;})
    ];

    # Stripping the upstream Bun executable corrupts its ELF version metadata.
    dontStrip = true;

    buildPhase = ''
      runHook preBuild
      node-gyp rebuild --directory node_modules/node-pty
      mkdir -p out
      cp -r ${finalAttrs.pnpmDeps}/orcad-watchers out/.orcad-watchers
      chmod -R u+w out/.orcad-watchers
      install -m755 ${finalAttrs.pnpmDeps}/bun-runtime bun-runtime
      patchelf --set-interpreter ${pkgs.stdenv.cc.bintools.dynamicLinker} \
        --set-rpath ${lib.makeLibraryPath [pkgs.glibc]} bun-runtime
      ORCAD_BUILD_TARGET=linux-x64-glibc \
        ORCAD_BUILD_TARGET_IS_CURRENT=1 \
        ORCAD_BUN_RUNTIME_PATH="$PWD/bun-runtime" \
        LD_LIBRARY_PATH=${lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib]} \
        node config/scripts/build-orcad.mjs
      rm -r out/.orcad-watchers
      patchelf --set-rpath ${lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib]} \
        out/orcad/node_modules/@parcel/watcher/watcher.node
      node node_modules/typescript/bin/tsc -p config/tsconfig.cli.json --outDir out --composite false --incremental false
      node config/scripts/verify-cli-bin.mjs --fix-executable --fix-package-json
      jq --arg version ${lib.escapeShellArg finalAttrs.version} '.version = $version' \
        out/package.json > out/package.json.new
      mv out/package.json.new out/package.json
      pnpm install --prod --offline --frozen-lockfile --ignore-scripts --trust-lockfile
      # Production installation discards the native addon built for the upstream checks.
      node-gyp rebuild --directory node_modules/node-pty
      patchelf --set-rpath ${lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib]} \
        "$(node -p "require.resolve('@parcel/watcher-linux-x64-glibc')")"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/orcad/native" "$out/bin"
      cp -r out node_modules "$out/lib/orcad/"
      cp -r native/windows-registry "$out/lib/orcad/native/"
      makeWrapper ${nodejs}/bin/node "$out/bin/orcad" \
        --add-flags "$out/lib/orcad/out/orcad/orcad.js" \
        --set ORCA_VERSION ${finalAttrs.version} \
        --set ORCA_APP_VERSION ${finalAttrs.version}
      makeWrapper ${nodejs}/bin/node "$out/bin/orca-ide" \
        --add-flags "$out/lib/orcad/out/cli/index.js"
      runHook postInstall
    '';

    # ELF fixups change the bytes covered by upstream's startup identity check.
    postFixup = ''
      "$out/bin/orcad" --orcad-profile-state-preflight \
        00000000-0000-4000-8000-000000000000 > preflight.json
      jq -er .artifactVersion preflight.json > "$out/lib/orcad/out/orcad/.version"
    '';

    meta = {
      description = "Orca coding-agent runtime without Electron";
      homepage = "https://github.com/stablyai/orca";
      license = lib.licenses.mit;
      mainProgram = "orcad";
      platforms = ["x86_64-linux"];
    };
  })
