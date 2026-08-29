{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        arch = "x86_64";
        os = "unknown-linux-musl";
        hash = "sha256-bjWsYLhsDox/i895e+i5IgYZn2JTIAtm/wVHJ2+M+lw=";
      };
      aarch64-linux = {
        arch = "aarch64";
        os = "unknown-linux-musl";
        hash = "sha256-xkrW5PgmCVUqNwaTZbUFKO9J6YauqySlOHgaGKQCdz0=";
      };
      aarch64-darwin = {
        arch = "aarch64";
        os = "apple-darwin";
        hash = "sha256-y25466gMG8MQpTP28cbJSDd3M7wG+eg3lJM04Eq96cY=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "codex: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "codex";
    version = "0.151.0";

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

    # Home Manager repoints this stable path when the forwarded agent changes.
    postFixup = ''
      wrapProgram "$out/bin/codex" \
        --run 'if [ -S "$HOME/.ssh/agent.sock" ]; then export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"; fi'
    '';

    meta = with lib; {
      description = "Lightweight coding agent that runs in your terminal";
      homepage = "https://github.com/openai/codex";
      changelog = "https://github.com/openai/codex/releases/tag/rust-v${version}";
      license = licenses.asl20;
      mainProgram = "codex";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
