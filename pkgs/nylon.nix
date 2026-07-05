{pkgs}:
pkgs.buildGoModule {
  pname = "nylon";
  version = "0-unstable-2026-07-05";

  # Fork of encodeous/nylon; per repo convention, pin only commits from the
  # fork's main branch. This is the fleet-wide reviewed commit deployed by
  # server-maintenance/playbooks/nylon-deploy.yml.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "nylon";
    rev = "dff5f9f3cf29a31bc4c8fdd7e4e34e4b592b39c2";
    hash = "sha256-mJxxz8VwPal+ZYYDpppBwWvFkL8tdFYbiq4s2TQhqlA=";
  };

  vendorHash = "sha256-ORofvATncvfpjOZtoQK349tOyeaO2hmmfF3m1xlitvo=";

  subPackages = ["."];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
  ];

  # Tests need network access and TUN devices.
  doCheck = false;

  meta = {
    description = "Nylon mesh router (WireGuard-based overlay with MPLS exits)";
    homepage = "https://github.com/gaoyifan/nylon";
    license = pkgs.lib.licenses.mit;
    mainProgram = "nylon";
    platforms = pkgs.lib.platforms.linux;
  };
}
