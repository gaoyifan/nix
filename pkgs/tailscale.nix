{pkgs}:
pkgs.tailscale.overrideAttrs {
  version = "1.102.2-yifan.4";

  # Fork with manual TLS certificates for Serve and multihomed UDP replies.
  # Per repo convention, this commit is pinned from the fork's main branch.
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "tailscale";
    rev = "2857ee72cd6ed26c2583493f437603f7ef71e6f5";
    hash = "sha256-uA1fsfW36fb19JnIPMUNpn+i4Y1e1Br203ibBeAsDts=";
  };

  vendorHash = "sha256-amKkUPszyhG4N5ZtrB01swBACYq76raSS+SQRneLmwc=";
}
