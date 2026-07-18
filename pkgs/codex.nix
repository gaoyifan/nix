{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        arch = "x86_64";
        os = "unknown-linux-musl";
        hash = "sha256-ma5I5HQ9psUw7NmYqy9+ZlcsCS9BkMiNyoI2wHsGzh0=";
      };
      aarch64-linux = {
        arch = "aarch64";
        os = "unknown-linux-musl";
        hash = "sha256-tDWYlrtUjgL91y6gyzOV/oqI0g06SkIcRIHlBPjokn8=";
      };
      aarch64-darwin = {
        arch = "aarch64";
        os = "apple-darwin";
        hash = "sha256-vL+nZlC2xYFQWqUXjB55nTf/EvxDo1/xbJC5f6dX5j8=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "codex: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "codex";
    version = "0.144.6";

    src = fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${platform.arch}-${platform.os}.tar.gz";
      inherit (platform) hash;
    };

    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;

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
