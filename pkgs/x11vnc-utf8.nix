{pkgs}:
pkgs.x11vnc.overrideAttrs (old: {
  patches = (old.patches or []) ++ [./x11vnc-utf8.patch];
  postPatch =
    (old.postPatch or "")
    + ''
      substituteInPlace src/xevents.c \
        --replace-fail '/usr/bin/xclip' '${pkgs.lib.getExe pkgs.xclip}'
    '';
})
