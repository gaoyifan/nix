{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        os = "linux";
        arch = "x64";
        hash = "sha256-J2vslQzbcLeu3rnZTTTr7tUkk2QDq5ho2AL2iOfzFWY=";
      };
      aarch64-linux = {
        os = "linux";
        arch = "arm64";
        hash = "sha256-nTiTUSfW1JXqKD5jtt/NlDBZTMntKockbsowgc52lac=";
      };
      aarch64-darwin = {
        os = "darwin";
        arch = "arm64";
        hash = "sha256-TsoYmlTdjkEK5iK5CLGTuPEayWoEFyqYmf7ksGN4KT0=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "cursor-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "cursor-cli";
    version = "2026.05.05-84a231c";

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
