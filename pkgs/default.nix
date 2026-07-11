pkgs:
{
  lazyssh = import ./lazyssh.nix {inherit pkgs;};
  dcv = import ./dcv.nix {inherit pkgs;};
  restic = import ./restic.nix {inherit pkgs;};
  mcat = import ./mcat.nix {inherit pkgs;};
  agy = import ./antigravity-cli.nix {inherit pkgs;};
  copilot-cli = import ./copilot-cli.nix {inherit pkgs;};
  codex = import ./codex.nix {inherit pkgs;};
  cursor-cli = import ./cursor-cli.nix {inherit pkgs;};
  tssh = import ./tssh.nix {inherit pkgs;};
  htop = import ./htop.nix {inherit pkgs;};
}
// pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  jip = import ./jip.nix {inherit pkgs;};
  nylon = import ./nylon.nix {inherit pkgs;};
}
