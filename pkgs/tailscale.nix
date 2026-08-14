{pkgs}:
pkgs.tailscale.overrideAttrs {
  version = "1.102.2-yifan";

  # Fork of tailscale/tailscale with manual TLS certificate support for Serve.
  # Per repo convention, this commit is pinned from the fork's main branch.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "tailscale";
    rev = "c68efb626a47c0723185a64db6976f3eaae366ba";
    hash = "sha256-K7MgTxWUvO0eGGqeQX37JPNFHbecL2U9Zpkw/SSp0iA=";
  };

  vendorHash = "sha256-amKkUPszyhG4N5ZtrB01swBACYq76raSS+SQRneLmwc=";
}
