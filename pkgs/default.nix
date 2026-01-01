# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#lazyssh'
pkgs: {
  lazyssh = pkgs.callPackage ./lazyssh.nix { };
}
