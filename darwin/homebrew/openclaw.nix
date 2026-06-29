{
  taps = [];

  brews = [
    # Network & remote access
    "iproute2mac" # Linux 'ip' command wrapper for macOS
    "mosh" # Mobile shell, more stable than SSH
    "mtr" # Traceroute + ping combined
    "netcat" # Network connection utility
    "nmap" # Port scanner and network discovery
    "socat" # Multipurpose network relay (netcat++)
    "tailscale" # WireGuard-based VPN mesh

    # Development
    "cargo-binstall" # Install prebuilt Rust binaries
    "cloudflare-wrangler" # Cloudflare Workers CLI
    "eget" # Download binaries from GitHub releases
    "fnm" # Fast Node.js version manager
    "gh" # GitHub CLI
    "git"
    "git-lfs" # Git large file storage
    "go"
    "rustup" # Rust toolchain manager
    "yarn" # JavaScript package manager

    # Shell & terminal
    "tmate" # Instant terminal sharing
    "watch" # Execute command periodically
    "zsh"

    # File & text utilities
    "fd" # Fast 'find' alternative
    "gawk" # GNU awk
    "gnu-sed" # GNU sed
    "grep" # GNU grep
    "jq" # JSON processor
    "ncdu" # NCurses disk usage analyzer
    "parallel" # Shell command parallelization
    "pv" # Monitor pipe data progress
    "rsync" # Fast incremental file transfer
    "tokei" # Fast code statistics

    # Monitoring & editing
    "neovim"
  ];

  casks = [];
}
