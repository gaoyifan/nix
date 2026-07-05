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
    rev = "01505b033012f30c0cca7fa118730dcb333b63df";
    hash = "sha256-A2v9q9u3srlQouUcIThhnA4hUy9ZFOPxsBZWBCPxRLM=";
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
