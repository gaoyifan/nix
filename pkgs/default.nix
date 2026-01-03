pkgs: {
  lazyssh = import ./lazyssh.nix {inherit pkgs;};
  dcv = import ./dcv.nix {inherit pkgs;};
}
