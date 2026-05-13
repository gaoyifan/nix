# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "bbd7d48fa2313492659763b3b75e43dc2b42652e";
    hash = "sha256-1ULbP0WVKZR3QyBo/HmfQOnWJuGr3dEKDfkZB07VJZI=";
  };
})
