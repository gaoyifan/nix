{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        platform = "linux-x64";
        asset = "cli_linux_x64.tar.gz";
        hash = "sha256-0XxCaXcyY2Hz2B8+oigg6WcWQoWSPeAgJH5GDcudFcM=";
      };
      aarch64-linux = {
        platform = "linux-arm";
        asset = "cli_linux_arm64.tar.gz";
        hash = "sha256-3rssBW44e+Y/34bUjfzJntH1I+UcUGer0RnXi9Nuihg=";
      };
      aarch64-darwin = {
        platform = "darwin-arm";
        asset = "cli_mac_arm64.tar.gz";
        hash = "sha256-CEiHtNRIXVpErEftbfarf5K6ATNwUFJPCpimkMhmIig=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "antigravity-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "antigravity-cli";
    version = "1.4.11-5180209989812224";

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
