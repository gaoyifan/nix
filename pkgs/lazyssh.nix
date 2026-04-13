# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "13edad830ad441e64d44274724711c10f6dc1f2c";
    hash = "sha256-/+PgkHeD6GODAY0OY8wpH0F0BwBOp3arbTzfwnarbtM=";
  };
})
