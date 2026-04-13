# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "8b91921cc9bdb070bf77dc4f68716c7a4e690eaa";
    hash = "sha256-Z9rOpTWcd6KbyZGnee5QKDqAyslUoB1s0EtqJKVik1A=";
  };
})
