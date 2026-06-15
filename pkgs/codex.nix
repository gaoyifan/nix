{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        arch = "x86_64";
        os = "unknown-linux-musl";
        hash = "sha256-SOWRlk1Luqt8BDPa7UHGXqjxUvwPHdIzSkLj3TIqSQY=";
      };
      aarch64-linux = {
        arch = "aarch64";
        os = "unknown-linux-musl";
        hash = "sha256-7GyATUFeQt0ozG+MbLUjiwDJr0v7WLY75V4m7E7ldsA=";
      };
      aarch64-darwin = {
        arch = "aarch64";
        os = "apple-darwin";
        hash = "sha256-yB6vG0ya7g6B4rOd7BdCpXthvmwQn4gR5/zUH1XCIz0=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "codex: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "codex";
    version = "0.140.0";

    src = fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${platform.arch}-${platform.os}.tar.gz";
      inherit (platform) hash;
    };

    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 codex-${platform.arch}-${platform.os} "$out/bin/codex"

      runHook postInstall
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
