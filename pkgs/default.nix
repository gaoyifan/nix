pkgs: {
  lazyssh = import ./lazyssh.nix {inherit pkgs;};
  dcv = import ./dcv.nix {inherit pkgs;};
  restic = import ./restic.nix {inherit pkgs;};
  codex = import ./codex.nix {inherit pkgs;};
  cursor-cli = import ./cursor-cli.nix {inherit pkgs;};
  openwarp-ssh-extension = import ./openwarp-ssh-extension.nix {inherit pkgs;};
}
