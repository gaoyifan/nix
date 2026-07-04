{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        os = "linux";
        arch = "x64";
        hash = "sha256-ww358eUYvWJuxYqXUo5ZeLzqbiNyGTqH2w04uFfcwZM=";
      };
      aarch64-linux = {
        os = "linux";
        arch = "arm64";
        hash = "sha256-VVZqv+h6nSg0bVDH3HHPzw3GE132GYtGYeTV3Wh5bRE=";
      };
      aarch64-darwin = {
        os = "darwin";
        arch = "arm64";
        hash = "sha256-SMvykcLijYG3n6DcvxirUL9Kx3ctDpqwlI7L1fWikVg=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "cursor-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "cursor-cli";
    version = "2026.07.01-41b2de7";

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

      # Allow disabling Max Mode for models whose variants are all flagged
      # isMaxMode (e.g. claude-fable-5). Upstream forces maxMode back to true
      # in setCurrentModelWithParameters whenever the selected variant has
      # isMaxMode, which also re-locks Max Mode on --resume. The GUI does not
      # do this. Drop the variant check so only supportsNonMaxMode counts.
      target=$(grep -lF 'supportsNonMaxMode||!0===' "$out/share/cursor-agent"/*.js)
      substituteInPlace $target \
        --replace-fail \
          'return!1===e.supportsNonMaxMode||!0===(null==t?void 0:t.isMaxMode)' \
          'return!1===e.supportsNonMaxMode'
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
