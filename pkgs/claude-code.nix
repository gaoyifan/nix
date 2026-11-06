{pkgs}: let
  inherit (pkgs) lib stdenvNoCC fetchurl;

  sources = {
    x86_64-linux = {
      asset = "linux-x64";
      hash = "sha256-2rr+yCyhMZ+kPYvjahD8YbHRGCHLmK1d8ErZXhmbju0=";
    };
    aarch64-linux = {
      asset = "linux-arm64";
      hash = "sha256-p+aH/RywVNZRx1iCI943hsmdTGgjZePDrh5Zzn86WR8=";
    };
    aarch64-darwin = {
      asset = "darwin-arm64";
      hash = "sha256-H1NYfpLe6OCJ+jSRiKTNpk+jSs5uewyi7ieN2qPMLr0=";
    };
  };
  platform = sources.${stdenvNoCC.hostPlatform.system};
in
  stdenvNoCC.mkDerivation rec {
    pname = "claude-code";
    version = "2.1.319";

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
