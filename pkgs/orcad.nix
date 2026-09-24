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
    version = "1.4.210";

    src = pkgs.fetchFromGitHub {
      owner = "stablyai";
      repo = "orca";
      tag = "v${finalAttrs.version}";
      hash = "sha256-TxjOAYqLUrEA6keJcWjU/2PBiApWgR/R9eDdUtcnxx0=";
    };

    pnpmDeps = pkgs.fetchPnpmDeps {
      inherit (finalAttrs) pname src;
      inherit pnpm;
      fetcherVersion = 4;
      # pnpm 12 treats the fetcher's empty --registry as an empty base URL.
      prePnpmInstall = ''export NIX_NPM_REGISTRY=https://registry.npmjs.org'';
      hash = "sha256-S0CRkdIhG9duioZmm8lsGzBy8bQ95HNaxERXoUAfwYU=";
    };

    nativeBuildInputs = [
      nodejs
      pnpm
      pkgs.pnpmConfigHook
      pkgs.python3
      pkgs.jq
      pkgs.makeBinaryWrapper
      (pkgs.node-gyp.override {inherit nodejs;})
    ];

    # A disconnected parent reports async send errors via the callback, not try/catch.
    # Without it, the upstream watcher smoke check can fail with an unhandled EPIPE.
    postPatch = ''
      substituteInPlace src/main/ipc/parcel-watcher-process-entry.ts \
        --replace-fail 'process.send?.(message)' 'process.send?.(message, () => {})'
    '';

    buildPhase = ''
      runHook preBuild
      node-gyp rebuild --directory node_modules/node-pty
      node config/scripts/build-orcad.mjs
      node node_modules/typescript/bin/tsc -p config/tsconfig.cli.json --outDir out --composite false --incremental false
      node config/scripts/verify-cli-bin.mjs --fix-executable --fix-package-json
      jq --arg version ${lib.escapeShellArg finalAttrs.version} '.version = $version' \
        out/package.json > out/package.json.new
      mv out/package.json.new out/package.json
      # Worktree creation loads this development dependency's dataset dynamically.
      install -Dm644 node_modules/emojibase-data/en/shortcodes/emojibase.json \
        out/orcad/node_modules/emojibase-data/en/shortcodes/emojibase.json
      pnpm install --prod --offline --frozen-lockfile --ignore-scripts --trust-lockfile
      # Production installation discards the native addon built for the upstream checks.
      node-gyp rebuild --directory node_modules/node-pty
      patchelf --set-rpath ${lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib]} \
        "$(node -p "require.resolve('@parcel/watcher-linux-x64-glibc')")"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/orcad" "$out/bin"
      cp -r out/orcad/. "$out/lib/orcad/"
      rm -r out/orcad
      cp -r out node_modules "$out/lib/orcad/"
      mkdir -p "$out/lib/orcad/native"
      cp -r native/windows-registry "$out/lib/orcad/native/"
      makeWrapper ${nodejs}/bin/node "$out/bin/orcad" \
        --add-flags "$out/lib/orcad/orcad.js" \
        --set ORCA_VERSION ${finalAttrs.version} \
        --set ORCA_APP_VERSION ${finalAttrs.version}
      makeWrapper ${nodejs}/bin/node "$out/bin/orca-ide" \
        --add-flags "$out/lib/orcad/out/cli/index.js"
      runHook postInstall
    '';

    meta = {
      description = "Orca coding-agent runtime without Electron";
      homepage = "https://github.com/stablyai/orca";
      license = lib.licenses.mit;
      mainProgram = "orcad";
      platforms = ["x86_64-linux"];
    };
  })
