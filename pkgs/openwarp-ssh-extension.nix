{pkgs}: let
  inherit (pkgs) lib stdenv;
  warpProtoApis = pkgs.fetchFromGitHub {
    owner = "warpdotdev";
    repo = "warp-proto-apis";
    rev = "aa2f9cde164a5b48ac01087d417d1188771f9b6d";
    hash = "sha256-6HIy65MopC5bmlmXYCyoa5d5YsO3+XpQHClQAC/bwxQ=";
  };
  warpWorkflows = pkgs.fetchFromGitHub {
    owner = "warpdotdev";
    repo = "workflows";
    rev = "793a98ddda6ef19682aed66364faebd2829f0e01";
    hash = "sha256-ICgkxlUUIfyhr0agZEk3KtGHX0uNRlRCKtz0iF2jd7o=";
  };
in
  pkgs.rustPlatform.buildRustPackage rec {
    pname = "openwarp-ssh-extension";
    version = "2026.05.08.preview";

    src = pkgs.fetchFromGitHub {
      owner = "zerx-lab";
      repo = "warp";
      rev = "v${version}";
      hash = "sha256-JmkpzT/kE5fkarCcvgWw9wdjBvQiaV4ePIM8Tk4OvgI=";
    };

    cargoHash = "sha256-VMeU9docv9SWQHYpNZGoaNy92HNEoC8ZN1ECvJpvyuA=";

    prePatch = ''
      find "$cargoDepsCopy" -type d -exec chmod u+rwx {} +
      find "$cargoDepsCopy" -type f -exec chmod u+rw {} +
      cp ${warpProtoApis}/apis/multi_agent/v1/*.proto "$cargoDepsCopy"/
      for manifest in "$cargoDepsCopy"/source-git-*/warp-workflows-*/Cargo.toml; do
        workflow_root="$(dirname "$(dirname "$manifest")")"
        rm -rf "$workflow_root/specs"
        cp -R --no-preserve=mode ${warpWorkflows}/specs "$workflow_root/specs"
      done
    '';

    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
      protobuf
    ];

    buildInputs =
      (with pkgs; [
        freetype
        openssl
      ])
      ++ lib.optionals stdenv.hostPlatform.isLinux (with pkgs; [
        alsa-lib
        dbus
        expat
        fontconfig
        libgit2
        libxkbcommon
      ]);

    cargoBuildFlags = ["--bin" "warp-oss"];
    doCheck = false;

    meta = with lib; {
      description = "OpenWarp binary used as the SSH extension remote server";
      homepage = "https://github.com/zerx-lab/warp";
      license = licenses.agpl3Only;
      mainProgram = "warp-oss";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
