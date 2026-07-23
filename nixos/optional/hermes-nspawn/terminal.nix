{
  aptProxyAddress,
  lib,
  managedSkills,
  newApiBaseUrl,
  pkgs,
}: let
  tesseractWithLanguages = pkgs.tesseract.override {
    enableLanguages = [
      "eng"
      "chi_sim"
    ];
  };
  documentPython = pkgs.python3.withPackages (pythonPackages:
    with pythonPackages; [
      markitdown
      pdf2image
      pdfplumber
      pillow
      pypdf
      ((pytesseract.override {tesseract = tesseractWithLanguages;}).overridePythonAttrs {
        # Upstream tests require French and OSD data, which this
        # English/Chinese-only Tesseract intentionally omits.
        doCheck = false;
      })
      reportlab
    ]);
  nixConfig = pkgs.writeTextDir "etc/nix/nix.conf" ''
    build-users-group =
    experimental-features = nix-command flakes
    extra-substituters = https://nix-cache.yfgao.net?priority=50
    extra-trusted-public-keys = nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4=
  '';
  codexCli = pkgs.writeShellScriptBin "codex" ''
    exec ${pkgs.nix}/bin/nix run \
      "github:gaoyifan/nix#codex" -- \
      --config 'model_provider="newapi"' \
      --config 'model_providers.newapi.name="New API"' \
      --config 'model_providers.newapi.base_url="${newApiBaseUrl}"' \
      --config 'model_providers.newapi.env_key="NEWAPI_API_KEY"' \
      "$@"
  '';
  ytDlp = pkgs.writeShellScriptBin "yt-dlp" ''
    exec ${pkgs.uv}/bin/uvx \
      --from 'yt-dlp[default,curl-cffi]@latest' \
      yt-dlp "$@"
  '';
  packages = [
    pkgs.bashInteractive
    pkgs.bind.dnsutils
    pkgs.cacert
    codexCli
    pkgs.coreutils
    pkgs.curl
    pkgs.deno
    documentPython
    pkgs.ffmpeg
    pkgs.file
    pkgs.findutils
    pkgs.fontconfig
    pkgs.gawk
    pkgs.git
    pkgs.gnugrep
    pkgs.gnused
    pkgs.iproute2
    pkgs.iputils
    pkgs.jq
    pkgs.lark-cli
    pkgs.libreoffice
    pkgs.netcat-openbsd
    pkgs.nix
    pkgs.node-docx
    pkgs.nodejs_22
    pkgs.pandoc
    pkgs."poppler-utils"
    pkgs.procps
    pkgs.qpdf
    tesseractWithLanguages
    pkgs.util-linux
    pkgs.uv
    ytDlp
  ];
  aptProxy = pkgs.writeTextDir "etc/apt/apt.conf.d/01proxy" ''
    Acquire::http::Proxy "http://${aptProxyAddress}:3142";
  '';
  ytDlpConfig = pkgs.writeTextDir "root/.config/yt-dlp/config" ''
    --remote-components ejs:npm
  '';
  fontConfig = pkgs.runCommand "hermes-fontconfig" {} ''
    mkdir -p $out/etc/fonts
    cp ${pkgs.makeFontsConf {fontDirectories = [pkgs.noto-fonts-cjk-sans];}} $out/etc/fonts/fonts.conf
  '';
  debianBase = pkgs.dockerTools.pullImage {
    imageName = "debian";
    imageDigest = "sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd";
    hash = "sha256-qSBIO82bf1xEUY3iQkhyrtvTUvt+QbJVTTGm5Bd4BKI=";
    finalImageName = "debian";
    finalImageTag = "trixie-slim";
  };
  imageName = "localhost/hermes-terminal";
  image = pkgs.dockerTools.buildLayeredImageWithNixDb {
    name = imageName;
    fromImage = debianBase;
    compressor = "zstd";
    contents = packages ++ [aptProxy fontConfig nixConfig ytDlpConfig];
    config = {
      Cmd = ["/bin/bash"];
      WorkingDir = "/workspace";
      Env = [
        "LANG=C.UTF-8"
        "LC_ALL=C.UTF-8"
        "FONTCONFIG_FILE=/etc/fonts/fonts.conf"
        "HERMES_HOME=/root/.hermes"
        "LARKSUITE_CLI_NO_SKILLS_NOTIFIER=1"
        "LARKSUITE_CLI_NO_UPDATE_NOTIFIER=1"
        "NODE_PATH=${pkgs.node-docx}/lib/node_modules"
        "PATH=${lib.makeBinPath packages}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
    };
  };
in {
  inherit image;
  imageRef = "${imageName}:${image.imageTag}";
  volumes = [
    "${managedSkills}:${managedSkills}:ro"
    "/var/lib/hermes/.lark-cli:/root/.lark-cli:idmap=uids=1000-0-1;gids=1000-0-1"
    "/var/lib/hermes/.local/share/lark-cli:/root/.local/share/lark-cli:idmap=uids=1000-0-1;gids=1000-0-1"
  ];
}
