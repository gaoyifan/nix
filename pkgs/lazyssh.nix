# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (_: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "537f1196b9968867526614714c172b7bc8cca96f";
    hash = "sha256-03CWeEdJc1TfpX8Pxb0ukiHKwO/IVXQQjT1iPQugwYQ=";
  };
})
