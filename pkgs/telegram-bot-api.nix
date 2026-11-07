{pkgs}:
pkgs.telegram-bot-api.overrideAttrs (old: {
  postPatch =
    (old.postPatch or "")
    + ''
      substituteInPlace telegram-bot-api/Client.h \
        --replace-fail \
          "static constexpr int32 MAX_DOWNLOAD_FILE_SIZE = 20 << 20;" \
          "static constexpr int32 MAX_DOWNLOAD_FILE_SIZE = 512 << 20;"
    '';
})
