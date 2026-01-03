# Custom dcv package (Docker Container Viewer)
{pkgs}: let
  lib = pkgs.lib;
in
  pkgs.buildGoModule rec {
    pname = "dcv";
    version = "0.3.1";

    nativeBuildInputs = [
      pkgs.gnumake
    ];

    src = pkgs.fetchFromGitHub {
      owner = "tokuhirom";
      repo = "dcv";
      rev = "v${version}";
      hash = "sha256-OwfGZq+ce6RNb5dhNHsQ15iMPoEp7QlaYIUVYIiVqmI=";
    };

    vendorHash = "sha256-uXv+ITiPVVKibvyZudWbUFEHeudoat7v18yO5HpoobE=";

    subPackages = ["."];

    preBuild = ''
      # dcv embeds helper binaries for talking to Docker inside DinD containers.
      make build-helpers
    '';

    ldflags = [
      "-s"
      "-w"
    ];

    meta = with lib; {
      description = "Terminal UI for monitoring Docker containers and Docker Compose projects";
      homepage = "https://github.com/tokuhirom/dcv";
      license = licenses.mit;
      mainProgram = "dcv";
    };
  }
