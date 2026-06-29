# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "d6f06143bcd1c2d4de8dc5162ad45341b3dcbbea";
    hash = "sha256-o7FyY0rE7pGANfw0khhbshKsLruxstEl/f4mrrImNCc=";
  };
})
