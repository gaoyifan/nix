{pkgs}: let
  inherit (pkgs) lib stdenvNoCC fetchurl;

  sources = {
    x86_64-linux = {
      asset = "linux-x64";
      hash = "sha256-Z03roLupruR59FA8Q4tJMDtv3TBLmkcbFJd6rsUhVFM=";
    };
    aarch64-linux = {
      asset = "linux-arm64";
      hash = "sha256-riKVri2hVpNr9YMasBlxzpJNDJoK8XTijZb/+o1foKY=";
    };
    aarch64-darwin = {
      asset = "darwin-arm64";
      hash = "sha256-R1UXyqYR4zGKLymPoHEofsmJVVON94xY9wnswB5a4tM=";
    };
  };
  platform = sources.${stdenvNoCC.hostPlatform.system};
in
  stdenvNoCC.mkDerivation rec {
    pname = "claude-code";
    version = "2.1.300";

    src = fetchurl {
      url = "https://downloads.claude.ai/claude-code-releases/${version}/${platform.asset}/claude";
      inherit (platform) hash;
    };

    dontUnpack = true;
    # Stripping the embedded Bun executable discards the application payload.
    dontStrip = true;

    nativeBuildInputs =
      [pkgs.makeBinaryWrapper]
      ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
        pkgs.autoPatchelfHook
      ];

    installPhase = ''
      runHook preInstall

      install -Dm755 "$src" "$out/bin/claude"
      wrapProgram "$out/bin/claude" \
        --set DISABLE_AUTOUPDATER 1 \
        --set DISABLE_INSTALLATION_CHECKS 1 \
        --set-default CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1 \
        ${lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [pkgs.alsa-lib]} \
        --prefix PATH : ${lib.makeBinPath [
          pkgs.procps
          pkgs.bubblewrap
          pkgs.socat
        ]}
      ''}

      runHook postInstall
    '';

    meta.platforms = builtins.attrNames sources;
  }
