{pkgs}:
pkgs.buildGoModule {
  pname = "nylon";
  version = "0-unstable-2026-08-15-f20427e";

  # Fork of encodeous/nylon; per repo convention, pin only commits from the
  # fork's main branch.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "nylon";
    rev = "f20427e9367ae3f66485d85c1be0a08ec612dee2";
    hash = "sha256-4Fm0SMaXUIQkAID6H0P/g1MZMCze7LNfbbsR0kgH5m4=";
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
