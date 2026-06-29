{pkgs}:
pkgs.buildGo125Module rec {
  pname = "tssh";
  version = "0.1.25-unstable-2026-06-29";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "trzsz-ssh";
    rev = "0d9b2576d2c9a1ff22adade6b61d66d7e476be1e";
    hash = "sha256-4JjqMBxhtSRsVFEZltmB0A8wrO6cXbDg82XI4XI5rf4=";
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
