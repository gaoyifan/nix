{pkgs}:
pkgs.buildGoModule {
  pname = "nylon";
  version = "0-unstable-2026-07-23-bc83908";

  # Fork of encodeous/nylon; per repo convention, pin only commits from the
  # fork's main branch. This is the reviewed commit pinned by
  # server-maintenance/playbooks/nylon-deploy.yml.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "nylon";
    rev = "bc83908f6707c99cb55afe8283fa32d4fc0a2e0a";
    hash = "sha256-afEMdePNx6l1PNq9hdtFy7qroMtgJNfHlL8PHHvhc5I=";
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
