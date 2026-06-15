{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        os = "linux";
        arch = "x64";
        hash = "sha256-M7IrDE/QOXqJ/BuQjkU2uwqPsJ2v+XrPUZ++x2VpzLM=";
      };
      aarch64-linux = {
        os = "linux";
        arch = "arm64";
        hash = "sha256-cD46R6R7uq5NVLSPhgp4Ctrla/2/uM/M9Xjd29VyE4I=";
      };
      aarch64-darwin = {
        os = "darwin";
        arch = "arm64";
        hash = "sha256-Se2EDjq0ahKZaJB9v+8G5Fnu+y/KHE/sU461YOG1m6w=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "cursor-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "cursor-cli";
    version = "2026.06.15-18-00-12-6f5a2cf";

    src = fetchurl {
      url = "https://downloads.cursor.com/lab/${version}/${platform.os}/${platform.arch}/agent-cli-package.tar.gz";
      inherit (platform) hash;
    };

    sourceRoot = ".";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
      pkgs.zlib
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -dm755 "$out/share/cursor-agent"
      cp -R dist-package/. "$out/share/cursor-agent/"
      chmod -R u+w "$out/share/cursor-agent"
      patchShebangs "$out/share/cursor-agent/cursor-agent"
      substituteInPlace "$out/share/cursor-agent/cursor-agent" \
        --replace-fail "set -euo pipefail" "set -euo pipefail
      export PATH=${lib.makeBinPath [pkgs.coreutils]}:\$PATH"

      install -dm755 "$out/bin"
      ln -s "$out/share/cursor-agent/cursor-agent" "$out/bin/cursor-agent"
      ln -s "$out/share/cursor-agent/cursor-agent" "$out/bin/agent"

      runHook postInstall
    '';

    meta = with lib; {
      description = "Cursor Agent CLI";
      homepage = "https://cursor.com/cli";
      license = licenses.unfree;
      mainProgram = "cursor-agent";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
