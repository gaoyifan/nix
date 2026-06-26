{pkgs}:
pkgs.buildGo125Module rec {
  pname = "tssh";
  version = "0.1.25-unstable-2026-06-26";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "trzsz-ssh";
    rev = "2e82d47b9c61702116b7a8de41e9fe0b9d8164e7";
    hash = "sha256-XYCoZmpmb4lNlLxZIqFlpzttNWG53JoYZyaT8JhwBP4=";
  };

  vendorHash = "sha256-cEV1w4VQUciifTKDhBvgLnqw5OHhbz7OqsgcXxKZ73M=";

  subPackages = ["cmd/tssh"];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "SSH client with trzsz and UDP roaming support";
    homepage = "https://github.com/trzsz/trzsz-ssh";
    license = pkgs.lib.licenses.mit;
    mainProgram = "tssh";
    platforms = pkgs.lib.platforms.unix;
  };
}
