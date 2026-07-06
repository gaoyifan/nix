{pkgs}:
pkgs.buildGoModule {
  pname = "nylon";
  version = "0-unstable-2026-07-06";

  # Fork of encodeous/nylon; per repo convention, pin only commits from the
  # fork's main branch. This is the fleet-wide reviewed commit deployed by
  # server-maintenance/playbooks/nylon-deploy.yml.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "nylon";
    rev = "f679630ecac4f543d8666db9b3abb062fde822e4";
    hash = "sha256-Q8qFgIH3/FJmDqW1X7ksKIwZIXNhWmcfI5ILomiH98o=";
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
