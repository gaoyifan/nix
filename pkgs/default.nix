pkgs:
{
  lazyssh = import ./lazyssh.nix {inherit pkgs;};
  dcv = import ./dcv.nix {inherit pkgs;};
  restic = import ./restic.nix {inherit pkgs;};
  codex = import ./codex.nix {inherit pkgs;};
  cursor-cli = import ./cursor-cli.nix {inherit pkgs;};
}
// pkgs.lib.optionalAttrs
(builtins.elem pkgs.stdenv.hostPlatform.system [
  "x86_64-linux"
  "aarch64-darwin"
]) {
  # Only expose openwarp-ssh-extension on systems where upstream actually
  # publishes a warp-oss artifact (see ../pkgs/openwarp-ssh-extension.nix).
  # Hiding it on other systems keeps `nix flake check --all-systems` clean
  # without forcing NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM.
  openwarp-ssh-extension = import ./openwarp-ssh-extension.nix {inherit pkgs;};
}
