{pkgs}:
pkgs.buildGoModule {
  pname = "nylon";
  version = "0-unstable-2026-07-21-97f5121";

  # Fork of encodeous/nylon; per repo convention, pin only commits from the
  # fork's main branch. This is the reviewed commit pinned by
  # server-maintenance/playbooks/nylon-deploy.yml.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "nylon";
    rev = "97f512154e584b8163962fc6d2af652cbb672cd8";
    hash = "sha256-bNkNOEEf6VQsilsNSDpOj8jHkztY0FHSuYYi+k+iEq0=";
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
