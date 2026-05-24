{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        os = "linux";
        arch = "x64";
        hash = "sha256-PjKk0d4x8s2XXSjKD3n0hoo5FHgwU5YmMhbT/9Mij48=";
      };
      aarch64-linux = {
        os = "linux";
        arch = "arm64";
        hash = "sha256-R4VepNtIS2K2/lgtMfEtpvnt+IixZ5DsAJ2sTs7WL7g=";
      };
      aarch64-darwin = {
        os = "darwin";
        arch = "arm64";
        hash = "sha256-DR0q98wo6Ifcx+lDvuG2WaGkzTbcz45Hzyo5U8Z4jSs=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "copilot-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "copilot-cli";
    version = "1.0.52";

    src = fetchurl {
      url = "https://github.com/github/copilot-cli/releases/download/v${version}/copilot-${platform.os}-${platform.arch}.tar.gz";
      inherit (platform) hash;
    };

    sourceRoot = ".";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
    ];

    dontConfigure = true;
    dontBuild = true;
    # `strip -S -p` on the upstream arm64 Linux binary produces anonymous NOTE
    # sections that make patchelf abort during autoPatchelfHook.
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 copilot "$out/bin/copilot"

      runHook postInstall
    '';

    meta = with lib; {
      description = "GitHub Copilot CLI";
      homepage = "https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli";
      changelog = "https://github.com/github/copilot-cli/releases/tag/v${version}";
      license = licenses.unfree;
      mainProgram = "copilot";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
