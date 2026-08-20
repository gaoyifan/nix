{pkgs}: let
  inherit (pkgs) fetchurl lib stdenv;

  platform =
    {
      x86_64-linux = {
        asset = "agent-browser-linux-x64";
        hash = "sha256-aerfXY1gA6BqXNL5FOuyYcd1T+EzWpGQEiwzTpGQl4k=";
      };
      aarch64-linux = {
        asset = "agent-browser-linux-arm64";
        hash = "sha256-ynC/fC0mmhUrOCTLtlvvt7gli4qhzzR2fGStoqvD18g=";
      };
      aarch64-darwin = {
        asset = "agent-browser-darwin-arm64";
        hash = "sha256-1oCnqWq4bpq50rVxsSkZt2HpNoKtHecUu9WshJyNfJw=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "agent-browser: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "agent-browser";
    version = "0.34.0";

    src = fetchurl {
      url = "https://github.com/vercel-labs/agent-browser/releases/download/v${version}/${platform.asset}";
      inherit (platform) hash;
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/agent-browser"
      runHook postInstall
    '';

    meta = with lib; {
      description = "Headless browser automation CLI for AI agents";
      homepage = "https://github.com/vercel-labs/agent-browser";
      license = licenses.asl20;
      mainProgram = "agent-browser";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      sourceProvenance = with sourceTypes; [binaryNativeCode];
    };
  }
