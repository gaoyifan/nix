{pkgs}:
pkgs.telegram-bot-api.overrideAttrs (old: {
  version = "10.2";

  src = pkgs.fetchFromGitHub {
    owner = "tdlib";
    repo = "telegram-bot-api";
    rev = "adfd7f6a8e990272851777eeb3ae0def4216f161";
    hash = "sha256-sICBisUDMirUOMN5ORQ2B9Wo8KC91hIn1sHyt2xClJ0=";
    fetchSubmodules = true;
  };

  postPatch =
    (old.postPatch or "")
    + ''
      substituteInPlace telegram-bot-api/Client.h \
        --replace-fail \
          "static constexpr int32 MAX_DOWNLOAD_FILE_SIZE = 20 << 20;" \
          "static constexpr int32 MAX_DOWNLOAD_FILE_SIZE = 128 << 20;"
    '';
})
