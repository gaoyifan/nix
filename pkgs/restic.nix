{pkgs}:
pkgs.restic.overrideAttrs (_oldAttrs: {
  pname = "restic";

  # Keep completion/manpage generation, but avoid wrapping restic with
  # openssh/rclone in PATH to keep the closure minimal.
  postInstall = pkgs.lib.optionalString (pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform) ''
    $out/bin/restic generate \
      --zsh-completion restic.zsh \
      --man .
    installShellCompletion --zsh restic.zsh
    installManPage *.1
  '';
})
