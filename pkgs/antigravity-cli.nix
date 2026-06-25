{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  platform =
    {
      x86_64-linux = {
        platform = "linux-x64";
        asset = "cli_linux_x64.tar.gz";
        hash = "sha256-fjB132jrrViqHPQiMenYuDvyiVtbBYqxc2sLY4PHUAg=";
      };
      aarch64-linux = {
        platform = "linux-arm";
        asset = "cli_linux_arm64.tar.gz";
        hash = "sha256-oDZ+WHWsG4imwLFjyG69XRPJvvkH9EaaZRb/aQIb8tQ=";
      };
      aarch64-darwin = {
        platform = "darwin-arm";
        asset = "cli_mac_arm64.tar.gz";
        hash = "sha256-U/cwihF/cP5+7KSmkAToI5yOoYydguR5ZrKQMytpuCk=";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "antigravity-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation rec {
    pname = "antigravity-cli";
    version = "1.0.12-6156052174077952";

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
      ln -s "$out/bin/agy" "$out/bin/antigravity"

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
