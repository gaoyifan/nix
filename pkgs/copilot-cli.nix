{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        os = "linux";
        arch = "x64";
        hash = "sha256-KnnHamOBoJ2Olt3ir/wiz9MzY1A0gqT5CgbFRr2eHM0=";
      };
      aarch64-linux = {
        os = "linux";
        arch = "arm64";
        hash = "sha256-cQbx5/GAiA9mJb4+cIXxn28foj9qlOHWjckpKS+fdq4=";
      };
      aarch64-darwin = {
        os = "darwin";
        arch = "arm64";
        hash = "sha256-4bzXcKTbB1YZj/DMO3vJKC4DFgwyyYt8SnPkObBpPw4=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "copilot-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "copilot-cli";
    version = "1.0.72";

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
