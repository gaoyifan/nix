{pkgs}:
pkgs.znapzend.overrideAttrs (oldAttrs: {
  postPatch =
    oldAttrs.postPatch
    + ''
      substituteInPlace lib/ZnapZend.pm \
        --replace-fail /usr/sbin/sendmail /run/wrappers/bin/sendmail
    '';
})
