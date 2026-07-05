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
    rev = "de1345908c54ea2e97e5ba8ef763439b6e4d7788";
    hash = "sha256-jrM39GukBfyblNtQWM0aFAgcNYF1bJFd2GP8vi8dYMQ=";
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
