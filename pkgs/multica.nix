{pkgs}: let
  inherit (pkgs) fetchurl lib stdenvNoCC;

  platform =
    {
      x86_64-linux = {
        os = "linux";
        arch = "amd64";
        hash = "sha256-Q7C3dmOSCsCWDw1iE35cX+XxlYs5vQFtZ2FG9U6PdJQ=";
      };
      aarch64-linux = {
        os = "linux";
        arch = "arm64";
        hash = "sha256-6NtRiv6gPtSPvCbTjdT8YN1889n3C8nbvjxwKjJyZ2U=";
      };
      aarch64-darwin = {
        os = "darwin";
        arch = "arm64";
        hash = "sha256-tLrhABwwqHDHhLGRI0N9+fCTCPdQppnONpOHe6b/xdE=";
      };
    }
    .${
      pkgs.stdenv.hostPlatform.system
    }
    or (throw "multica: unsupported system ${pkgs.stdenv.hostPlatform.system}");
in
  stdenvNoCC.mkDerivation rec {
    pname = "multica";
    version = "0.5.0";

    src = fetchurl {
      url = "https://github.com/multica-ai/multica/releases/download/v${version}/multica-cli-${version}-${platform.os}-${platform.arch}.tar.gz";
      inherit (platform) hash;
    };

    sourceRoot = ".";
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 multica "$out/bin/multica"
      install -Dm644 LICENSE NOTICE README.md README.zh.md -t "$out/share/doc/multica"

      runHook postInstall
    '';

    meta = {
      description = "Workspace for coordinating AI coding agents";
      homepage = "https://github.com/multica-ai/multica";
      license = lib.licenses.asl20;
      mainProgram = "multica";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
