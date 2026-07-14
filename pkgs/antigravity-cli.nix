{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        platform = "linux-x64";
        asset = "cli_linux_x64.tar.gz";
        hash = "sha256-B1QBA0eSba8AyWc0z89Z7mBD6rI+/DW5my1iqthNxvA=";
      };
      aarch64-linux = {
        platform = "linux-arm";
        asset = "cli_linux_arm64.tar.gz";
        hash = "sha256-Wc+ewPWmlP2c9hImLRUoVzaP3IGdsRkr0/4SGbomJU8=";
      };
      aarch64-darwin = {
        platform = "darwin-arm";
        asset = "cli_mac_arm64.tar.gz";
        hash = "sha256-ULdgxQ/yiDQv1LuLHCHVrHLaddxHtocLb+ZF6TcMle4=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "antigravity-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "antigravity-cli";
    version = "1.1.2-5174998495789056";

    src = fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}/${platform.platform}/${platform.asset}";
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

    installPhase = ''
      runHook preInstall

      install -Dm755 antigravity "$out/bin/agy"

      runHook postInstall
    '';

    meta = with lib; {
      description = "Google Antigravity CLI";
      homepage = "https://antigravity.google/cli";
      license = licenses.unfree;
      mainProgram = "agy";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
