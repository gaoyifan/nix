{pkgs}:
pkgs.buildGo125Module rec {
  pname = "tssh";
  version = "0.1.25-unstable-2026-06-26";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "trzsz-ssh";
    rev = "6885a2034bcc9cc1491816dbaedc8b23a90a9add";
    hash = "sha256-+jiynzU7Q5n+y0ULSNOADTbyyVJPsXCQ+FM3dwdyH+k=";
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
