{pkgs}:
pkgs.buildGoModule {
  pname = "nylon";
  version = "0-unstable-2026-11-13-2b9c440";

  # Fork of encodeous/nylon; per repo convention, pin only commits from the
  # fork's main branch.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "nylon";
    rev = "2b9c440ad5c814aa62761d15e27c8132729d1974";
    hash = "sha256-1cqOOm4MnjtF4v4B/ybkSjAr3KuTf3188dIFc0QzkS4=";
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
