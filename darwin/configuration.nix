# Darwin system configuration
{pkgs, ...}: let
  username = "yifan";
in {
  # User configuration - required for home-manager
  users.users.${username}.home = "/Users/${username}";

  # Nix settings - system-wide configuration
  nix = {
    settings = {
      # Trusted users for the nix daemon
      trusted-users = [
        "root"
        username
      ];

      # Enable experimental features
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Automatically accept flake config (extra-substituters, etc.)
      accept-flake-config = true;
    };

    # Garbage collection
    gc.automatic = true;

    # Optimize store
    optimise.automatic = true;
  };

  # Add rustup bin to PATH for Rust toolchain
  environment.systemPath = ["/opt/homebrew/opt/rustup/bin"];
  environment.systemPackages = with pkgs; [
    nil # Nix language server
  ];

  system = {
    # Used for backwards compatibility
    stateVersion = 6;

    # Primary user for nix-darwin (required for homebrew, etc.)
    primaryUser = username;

    # Disable startup chime
    startup.chime = false;
  };

  # Enable Touch ID authentication for sudo
  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "uninstall";
    };

    taps = [
      "devnullvoid/pvetui"
    ];

    brews = [
      # Network diagnostics
      "arping" # Check if MAC addresses are taken on LAN
      "bandwhich" # Terminal bandwidth monitor by process
      "bmon" # Interface bandwidth monitor
      "croc" # Secure file transfer between computers
      "iftop" # Display interface bandwidth usage
      "iperf3" # Network bandwidth testing
      "iproute2mac" # Linux 'ip' command wrapper for macOS
      "mosh" # Mobile shell, more stable than SSH
      "mtr" # Traceroute + ping combined
      "nali" # IP geolocation and CDN provider lookup
      "netcat" # Network connection utility
      "nmap" # Port scanner and network discovery
      "proxychains-ng" # Force apps through proxy
      "socat" # Multipurpose network relay (netcat++)
      "tailscale" # WireGuard-based VPN mesh
      "telnet" # Telnet client
      "wakeonlan" # Send WOL magic packets
      "wireshark" # Network packet analyzer (CLI)

      # Development
      "cargo-binstall" # Install prebuilt Rust binaries
      "cloudflare-wrangler" # Cloudflare Workers CLI
      "doctl" # DigitalOcean CLI
      "eget" # Download binaries from GitHub releases
      "fnm" # Fast Node.js version manager
      "gh" # GitHub CLI
      "git"
      "git-lfs" # Git large file storage
      "go"
      "rustup" # Rust toolchain manager
      "step" # Smallstep CLI for certificates/PKI
      "yarn" # JavaScript package manager
      "tokuhirom/tap/dcv" # Docker Compose TUI viewer

      # Shell & terminal
      "asciinema" # Record and share terminal sessions
      "mcat" # Terminal image/video/markdown viewer
      "tmate" # Instant terminal sharing
      "tuios" # Terminal multiplexer (alternative to tmux)
      "watch" # Execute command periodically
      "zsh"

      # File & disk utilities
      "fd" # Fast 'find' alternative
      "ncdu" # NCurses disk usage analyzer
      "pv" # Monitor pipe data progress
      "renameutils" # Batch file renaming tools
      "rsync" # Fast incremental file transfer

      # Text & data processing
      "exiftool" # EXIF metadata reader/writer
      "gawk" # GNU awk
      "gnu-sed" # GNU sed
      "grep" # GNU grep
      "jq" # JSON processor
      "pandoc" # Document format converter

      # System monitoring
      "htop" # Interactive process viewer
      "macmon" # Apple Silicon performance monitor (sudoless)
      "nvtop" # GPU process monitor

      # Editors (neovim via Homebrew to avoid large nix closure on macOS)
      "neovim"

      # Other tools
      "gemini-cli" # Google Gemini AI CLI
      "parallel" # Shell command parallelization
      "tokei" # Fast code statistics
      "yt-dlp" # Video downloader (YouTube, etc.)
    ];

    casks = [
      # Password & Security
      "1password"
      "electrum" # Bitcoin wallet

      # AI Tools
      "antigravity"
      "chatgpt"
      "chatgpt-atlas"
      "cherry-studio"
      "codex"
      "lm-studio" # Local LLM runner

      # Development
      "cursor"
      "iterm2"
      "zed"
      "orbstack" # Docker/Linux VM alternative
      "vmware-fusion"
      "xquartz" # X11 server
      "macfuse" # User-space filesystem

      # Browsers
      "firefox"
      "google-chrome"

      # Notes & Documents
      "notion"
      "typora" # Markdown editor
      "calibre" # E-book manager

      # Media
      "iina" # Modern video player
      "vlc"
      "neteasemusic"
      "plex"
      "plex-htpc"
      "moonlight" # Game streaming client

      # Sync & Backup
      "syncthing-app"
      "kopiaui" # Backup tool GUI

      # System Tools
      "raycast" # Spotlight replacement
      "topnotch" # Hide MacBook notch
      "balenaetcher" # USB/SD flasher
      "raspberry-pi-imager"
      "pvetui" # Proxmox VE TUI

      # Fonts
      "font-inconsolata-for-powerline"
      "font-jetbrains-mono-nerd-font"

      # Input Method
      "squirrel-app" # Rime input method

      # Social
      "telegram"
      "voov-meeting" # Tencent Meeting

      # RSS
      "folo"

      # Games
      "playcover-community" # Run iOS apps on Apple Silicon
    ];
  };
}
