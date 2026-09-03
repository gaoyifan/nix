{pkgs}: let
  inherit (pkgs) fetchurl lib stdenv;

  platforms = {
    x86_64-linux = {
      asset = "linux-x64";
      hash = "sha256-je/WF8iu775XvT5abPP1V1D9kiYd1xMjmyRIJvqRBNc=";
    };
    aarch64-linux = {
      asset = "linux-arm64";
      hash = "sha256-RVbO4h0UewIujZSL9yytykKdTwMIxWg/dKDaPohWa7I=";
    };
    aarch64-darwin = {
      asset = "macos-arm64";
      hash = "sha256-JcSkVreMy/7sCX73CboNXUA3+Tm2lfs6M/x+HnG/oic=";
    };
  };
  platform =
    platforms.${stdenv.hostPlatform.system}
    or (throw "colliepwa: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "colliepwa";
    version = "1.3.0";

    src = fetchurl {
      url = "https://github.com/AltanS/collie/releases/download/v${version}/collie-${version}-${platform.asset}.tar.gz";
      inherit (platform) hash;
    };

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      pkgs.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall

      install -dm755 "$out/bin" "$out/lib/colliepwa"
      cp -R . "$out/lib/colliepwa/"
      ln -s ../lib/colliepwa/bin/collie "$out/bin/collie"

      runHook postInstall
    '';

    meta = with lib; {
      description = "PWA for managing Herdr agents from a phone";
      homepage = "https://colliepwa.dev";
      changelog = "https://github.com/AltanS/collie/releases/tag/v${version}";
      license = licenses.mit;
      mainProgram = "collie";
      sourceProvenance = [sourceTypes.binaryNativeCode];
      platforms = builtins.attrNames platforms;
    };
  }
