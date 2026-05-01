pkgs: {
  lazyssh = import ./lazyssh.nix {inherit pkgs;};
  dcv = import ./dcv.nix {inherit pkgs;};
  restic = import ./restic.nix {inherit pkgs;};
  codex = import ./codex.nix {inherit pkgs;};
}
