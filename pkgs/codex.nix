{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        arch = "x86_64";
        os = "unknown-linux-musl";
        hash = "sha256-iGuF5hGMC0MjRDfKAH++kjYRpTsQPQDg0650rvsg4jo=";
      };
      aarch64-linux = {
        arch = "aarch64";
        os = "unknown-linux-musl";
        hash = "sha256-MWG01TBP6ve++7D8tBv5p+5A4xun4+821AoAqjumy9A=";
      };
      aarch64-darwin = {
        arch = "aarch64";
        os = "apple-darwin";
        hash = "sha256-8GggLoqJjCQMjAaEAbzNMLp7VvYfX/zRSD1UXUeq89U=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "codex: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "codex";
    version = "0.128.0";

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
