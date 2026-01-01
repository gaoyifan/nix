# Custom lazyssh package using gaoyifan/lazyssh fork
# Overrides upstream nixpkgs lazyssh with different source
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  version = "0.3.0-yifan";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "f6258bf0d01c5d92a2c3363d97279dffe58fbf09";
    hash = "sha256-wZRcIOWvX2k44zLjZ5wwrrAWQoMJu+aVGgqGoRVYQJ8=";
  };
})
