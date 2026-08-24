{pkgs}:
pkgs.tailscale.overrideAttrs {
  version = "1.102.2-yifan.3";

  # Fork of tailscale/tailscale with manual TLS certificate support for Serve.
  # Per repo convention, this commit is pinned from the fork's main branch.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "tailscale";
    rev = "6b9de8135887e9d6a895e5c98e7d252e607b45f1";
    hash = "sha256-jH6118DEt6rtxELoIHkMabp7Jr3OqmnnYwD/D5P+pdg=";
  };

  vendorHash = "sha256-amKkUPszyhG4N5ZtrB01swBACYq76raSS+SQRneLmwc=";
}
