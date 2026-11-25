{pkgs}: let
  inherit (pkgs) lib stdenvNoCC fetchurl;

  platform =
    {
      x86_64-linux = {
        asset = "pi-linux-x64.tar.gz";
        hash = "sha256-PH8AcV61EuFlwNqMrTFNc8g7VNW/d0i+Stxhj8g1e2g=";
      };
      aarch64-linux = {
        asset = "pi-linux-arm64.tar.gz";
        hash = "sha256-r95kHWxZBNJpYN20Ijv1Y7CGDPGg68RDuF3v9n0Eh1M=";
      };
      aarch64-darwin = {
        asset = "pi-darwin-arm64.tar.gz";
        hash = "sha256-2P2OJMKlBUrjg9g7Jvbrb5UO32E5F+Q0pSOU9EzU2TM=";
      };
    }
    .${
      stdenvNoCC.hostPlatform.system
    }
    or (throw "pi-coding-agent: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
  stdenvNoCC.mkDerivation rec {
    pname = "pi-coding-agent";
    version = "1.6.1";

    src = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/${platform.asset}";
      inherit (platform) hash;
    };

    sourceRoot = "pi";

    nativeBuildInputs =
      [pkgs.makeWrapper]
      ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
        pkgs.autoPatchelfHook
      ];

    buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
      pkgs.libxcb
      pkgs.stdenv.cc.cc.lib
    ];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -dm755 "$out/bin" "$out/lib/pi-coding-agent"
      cp -R . "$out/lib/pi-coding-agent/"

      # Keep this example readable without making its non-Nix shebang a runtime reference.
      chmod -x "$out/lib/pi-coding-agent/examples/extensions/doom-overlay/doom/build.sh"

      # Home Manager repoints this stable path when the forwarded agent changes.
      makeWrapper \
        "$out/lib/pi-coding-agent/pi" \
        "$out/bin/pi" \
        --prefix PATH : ${lib.makeBinPath [
        pkgs.fd
        pkgs.ripgrep
      ]} \
        --run 'if [ -S "$HOME/.ssh/agent.sock" ]; then export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"; fi'

      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck

      # --help initializes the project trust store and needs a writable home.
      export HOME="$(mktemp -d)"
      test "$("$out/bin/pi" --version)" = "${version}"
      "$out/bin/pi" --help >/dev/null

      runHook postInstallCheck
    '';

    meta = with lib; {
      description = "Coding agent CLI with read, bash, edit, write tools and session management";
      homepage = "https://pi.dev/";
      changelog = "https://github.com/earendil-works/pi/releases/tag/v${version}";
      license = licenses.mit;
      mainProgram = "pi";
      sourceProvenance = [sourceTypes.binaryNativeCode];
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
