# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "8f29f6c12480024d56eed171a8c45c7eaa70d256";
    hash = "sha256-IDml59RHeTNmINZO+srXSLa7fjV49J6DRN0yncalLgo=";
  };
})
