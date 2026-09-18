{pkgs}:
pkgs.rustPlatform.buildRustPackage {
  pname = "tcp-transparent-repeater";
  version = "0.4.1";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "tcp-transparent-repeater";
    rev = "40f6b748e9982026b1467046abdd1847ce4e9eb5";
    hash = "sha256-QwyI+Gzc9DFnEARsl8lMEK+58bGn3gEBAM4aaMZjh+E=";
  };

  cargoHash = "sha256-UdZKcEWiwLBjEbx04CkAdIx+F5XZ3UoPs4W3aPC2xEc=";

  meta = {
    description = "TCP transparent repeater with fwmark preservation";
    homepage = "https://github.com/gaoyifan/tcp-transparent-repeater";
    license = pkgs.lib.licenses.mit;
    mainProgram = "tcp_transparent_repeater";
    platforms = pkgs.lib.platforms.linux;
  };
}
