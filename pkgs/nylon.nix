{pkgs}:
pkgs.buildGoModule {
  pname = "nylon";
  version = "0-unstable-2026-07-23-71d83f3";

  # Fork of encodeous/nylon; per repo convention, pin only commits from the
  # fork's main branch. This is the reviewed commit pinned by
  # server-maintenance/playbooks/nylon-deploy.yml.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "nylon";
    rev = "71d83f3b17ea5abdfe9b682429b0c7e295798f8e";
    hash = "sha256-xGB7ZhS/uaTY0ELLXJm038MZrIK6oyEmW+3Gj+x4S8k=";
  };

  vendorHash = "sha256-8lkcp/dyyONveEfikQaOSC53qHkwaCidgXgcFt06Bxs=";

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
