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
    "cloudflare-wrangler" # Cloudflare Workers CLI
    "fnm" # Fast Node.js version manager
    "git-lfs" # Git large file storage

    # Shell & terminal
    "watch" # Execute command periodically
    "zsh"

    # File & text utilities
    "gawk" # GNU awk
    "gnu-sed" # GNU sed
    "grep" # GNU grep
    "parallel" # Shell command parallelization

    # Monitoring & editing
    "neovim"
  ];

  casks = [];
}
