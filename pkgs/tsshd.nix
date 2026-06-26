{pkgs}:
pkgs.buildGo125Module rec {
  pname = "tsshd";
  version = "0.1.8";

  src = pkgs.fetchFromGitHub {
    owner = "trzsz";
    repo = "tsshd";
    rev = "v${version}";
    hash = "sha256-YqSSJA/jP8WRbfwC5fxFE4su01ZEPQNmiNRr96pDE1g=";
  };

  vendorHash = "sha256-HJWxphZuBh3gXPoEqL/EVGtwdWyW+cMSQhKyfSymKG0=";

  subPackages = ["cmd/tsshd"];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "UDP-based SSH server with roaming support";
    homepage = "https://github.com/trzsz/tsshd";
    license = pkgs.lib.licenses.mit;
    mainProgram = "tsshd";
    platforms = pkgs.lib.platforms.linux;
  };
}
