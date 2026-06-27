# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "c516a03f206992169f6b27b9ba08b2aa5bede662";
    hash = "sha256-/fCdihZ7PPqCDrrTtmRtAD+J1VGmm15ol4Qm0Fpiv+w=";
  };
})
