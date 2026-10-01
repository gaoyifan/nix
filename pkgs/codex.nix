{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        arch = "x86_64";
        os = "unknown-linux-musl";
        hash = "sha256-T8xHq1f1L/dTY5Uah2EUbNEMgoi9hv7UVIfbsgSha3E=";
      };
      aarch64-linux = {
        arch = "aarch64";
        os = "unknown-linux-musl";
        hash = "sha256-fw/kL/Iuz6Oke8SjT1sixCGLQxpOwKulHH2YKZ8HkAw=";
      };
      aarch64-darwin = {
        arch = "aarch64";
        os = "apple-darwin";
        hash = "sha256-AH30G2B9u8jSBLl0bOf+0tTObIE/RMMs7uVBdcp5ZSU=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "codex: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "codex";
    version = "0.160.0";

    src = fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${platform.arch}-${platform.os}.tar.gz";
      inherit (platform) hash;
    };

    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs =
      [pkgs.makeWrapper]
      ++ lib.optionals stdenv.hostPlatform.isLinux [
        pkgs.autoPatchelfHook
      ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
      pkgs.ncurses
    ];

    installPhase = ''
      runHook preInstall

      install -dm755 "$out/bin"
      install -Dm755 bin/codex "$out/bin/codex"
      install -Dm755 bin/codex-code-mode-host "$out/bin/codex-code-mode-host"
      install -Dm644 codex-package.json "$out/codex-package.json"
      cp -r codex-resources "$out/"
      cp -r codex-path "$out/"

      runHook postInstall
    '';

    # The daemon copies this package and checks bin/codex against the running
    # executable, so keep that entrypoint as the original binary.
    postFixup = ''
      makeWrapper "$out/bin/codex" "$out/bin/codex-launcher" \
        ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix PATH : ${lib.makeBinPath [pkgs.bubblewrap]}"} \
        --run 'if [ -S "$HOME/.ssh/agent.sock" ]; then export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"; fi'
    '';

    meta = with lib; {
      description = "Lightweight coding agent that runs in your terminal";
      homepage = "https://github.com/openai/codex";
      changelog = "https://github.com/openai/codex/releases/tag/rust-v${version}";
      license = licenses.asl20;
      mainProgram = "codex-launcher";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
