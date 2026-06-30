{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        os = "linux";
        arch = "x64";
        hash = "sha256-xtJR3iDRRBXr1q8Av7ao44VAlLSfpJ+3898r+mT22zs=";
      };
      aarch64-linux = {
        os = "linux";
        arch = "arm64";
        hash = "sha256-+NnWx7VL/VqYIA5no0Oe8yeAYfgTFSBJcQdianY8P2M=";
      };
      aarch64-darwin = {
        os = "darwin";
        arch = "arm64";
        hash = "sha256-nNG8o343lpfO39mazo39TYq3EZoPg076D0jqhynB4wE=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "copilot-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "copilot-cli";
    version = "1.0.67";

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
