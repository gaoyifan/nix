{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        arch = "x86_64";
        os = "unknown-linux-musl";
        hash = "sha256-y5M+w8thv0tfyI7s9eYUmCn6phclNbbvCvsBVL60qrg=";
      };
      aarch64-linux = {
        arch = "aarch64";
        os = "unknown-linux-musl";
        hash = "sha256-sYx1xJZFkY+uI766CrQcBfB5QWAVEKJFG6l/5RlXPDg=";
      };
      aarch64-darwin = {
        arch = "aarch64";
        os = "apple-darwin";
        hash = "sha256-cVaxmWJzXJz7VVzde6voxA55dogfhxK3gRmSGdLjpwc=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "codex: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "codex";
    version = "0.142.5";

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
