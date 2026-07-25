{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        asset = "omp-linux-x64";
        hash = "sha256-F6fi4cScvAkSnin79IzevRpUXQU/XK1ylcGJi26qQi4=";
      };
      aarch64-linux = {
        asset = "omp-linux-arm64";
        hash = "sha256-bTA6a2J6K/WFPupDNm6+YRTbsr+y41WhMzxuocZ4tBA=";
      };
      aarch64-darwin = {
        asset = "omp-darwin-arm64";
        hash = "sha256-8MArnxQmZoqq/7a5PFWYa6DU5ruXYsmjeOHPfzbSLX4=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "oh-my-pi: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "oh-my-pi";
    version = "17.1.3";

    src = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/${platform.asset}";
      inherit (platform) hash;
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall

      install -Dm755 "$src" "$out/bin/omp"

      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck

      test "$(HOME="$TMPDIR" "$out/bin/omp" --version)" = "omp/${version}"
      HOME="$TMPDIR" "$out/bin/omp" --help >/dev/null

      runHook postInstallCheck
    '';

    meta = with lib; {
      description = "AI coding agent with an integrated IDE, LSP, debugger, and subagents";
      homepage = "https://omp.sh";
      changelog = "https://github.com/can1357/oh-my-pi/releases/tag/v${version}";
      license = licenses.mit;
      mainProgram = "omp";
      sourceProvenance = [sourceTypes.binaryNativeCode];
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
