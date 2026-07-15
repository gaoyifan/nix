{pkgs}:
pkgs.tailscale.overrideAttrs {
  version = "1.98.8-yifan";

  # Fork of tailscale/tailscale with manual TLS certificate support for Serve.
  # Per repo convention, this commit is pinned from the fork's main branch.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "tailscale";
    rev = "7310d88f1d7f7f4cf97d8858064b7141cda81cfc";
    hash = "sha256-e+WKU4H0HTrr8EKL1G29/DWZrpMCst3jrLIa7I1kioM=";
  };

  vendorHash = "sha256-Sd2iLJ7eDfDYdIRuW4xuiKgzhQWJWGAnz97FJWrVRlE=";
}
