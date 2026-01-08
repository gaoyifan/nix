# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "b6c16a921a0e851839b7bf2c4307bc09ce0d93b7";
    hash = "sha256-B+5qo44rJ8w2dDwZgIBPFk+k216PLYPzUtI68oVa+K0=";
  };
})
