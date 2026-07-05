{pkgs}: let
  inherit (pkgs) lib stdenv rustPlatform installShellFiles buildPackages runCommand;

  mcat-unwrapped = rustPlatform.buildRustPackage (finalAttrs: {
    pname = "mcat-unwrapped";
    version = "0.6.2";

    src = pkgs.fetchFromGitHub {
      owner = "Skardyy";
      repo = "mcat";
      tag = "v${finalAttrs.version}";
      hash = "sha256-7QjnbdxUFeRDkIGnAcY2Wf8fLKuj1RuVbu0SUebOc5A=";
    };

    cargoHash = "sha256-JnSycAz/jFs9JgA3tqYZn64yNK0bv5SXEYyUOXjC4ug=";

    nativeBuildInputs = [
      installShellFiles
    ];

    checkFlags = [
      "--skip=stdin_svg_output_is_image"
    ];

    postInstall = let
      mcat =
        if stdenv.buildPlatform.canExecute stdenv.hostPlatform
        then builtins.placeholder "out"
        else buildPackages.mcat-unwrapped;
    in ''
      installShellCompletion --cmd mcat \
        --bash <(${mcat}/bin/mcat --generate bash) \
        --fish <(${mcat}/bin/mcat --generate fish) \
        --zsh <(${mcat}/bin/mcat --generate zsh)
    '';

    meta = with lib; {
      description = "Terminal image, video, directory, and Markdown viewer";
      homepage = "https://github.com/Skardyy/mcat";
      changelog = "https://github.com/Skardyy/mcat/blob/v${finalAttrs.version}/CHANGELOG.md";
      license = licenses.mit;
      mainProgram = "mcat";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  });
in
  runCommand "mcat"
  {
    pname = "mcat";
    inherit (mcat-unwrapped) version meta;
  }
  ''
    mkdir -p "$out/bin"
    ln -s "${mcat-unwrapped}/share" "$out/share"
    ln -s "${lib.getExe mcat-unwrapped}" "$out/bin/mcat"
  ''
