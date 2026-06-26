{pkgs}:
pkgs.buildGo125Module rec {
  pname = "tssh";
  version = "0.1.25-unstable-2026-06-26";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "trzsz-ssh";
    rev = "b1ebbfb1d24c0a66b2d790c055735fa007c9018c";
    hash = "sha256-BHMMKdOT2FMP3f4XJeUs6xnUVeVIonqE6ct91k1BS6k=";
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
