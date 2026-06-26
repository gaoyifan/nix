# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "ce9557389484380415af6c53dc84b420ee00b424";
    hash = "sha256-rXTSHpdjzF4m8BbM5Q6MGzO52RiqQP+JS/Lo3oTyiIM=";
  };
})
