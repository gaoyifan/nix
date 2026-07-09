{
  taps = [
    {
      name = "devnullvoid/pvetui";
      trusted = true;
    }
    {
      name = "anomalyco/tap";
      trusted = true;
    }
    {
      name = "ramonvermeulen/whosthere";
      trusted = true;
    }
    {
      name = "deskflow/tap";
      trusted = true;
    }
    {
      name = "gaoyifan/tap";
      trusted = true;
    }
    {
      name = "lucasgelfond/zerobrew";
      trusted = true;
    }
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
    "tsshd" # UDP-based SSH server with roaming support
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

    # Shell & terminal
    "asciinema" # Record and share terminal sessions
    "mcat" # Terminal image/video/markdown viewer
    "tmate" # Instant terminal sharing
    "tuios" # Terminal multiplexer (alternative to tmux)
    "watch" # Execute command periodically
    "zsh"
    "lucasgelfond/zerobrew/zerobrew" # Run Homebrew formulae in isolated environments

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
    "restic" # Backup program with deduplication and encryption

    # System monitoring
    "mactop" # Apple Silicon Monitor Top written in Go Lang
    "nvtop" # GPU process monitor

    # Editors (neovim via Homebrew to avoid large nix closure on macOS)
    "neovim"

    # AI Tools
    "anomalyco/tap/opencode"

    # Other tools
    "gemini-cli" # Google Gemini AI CLI
    "huggingface-cli" # Hugging Face CLI
    "parallel" # Shell command parallelization
    "tokei" # Fast code statistics
    "ffmpeg" # Audio/video processing toolkit
    "yt-dlp" # Video downloader (YouTube, etc.)
  ];

  casks = [
    # Password & Security
    "1password"
    "1password-cli"
    "electrum" # Bitcoin wallet
    "ramonvermeulen/whosthere/whosthere" # See who's on your network

    # AI Tools
    "chatgpt"
    "chatgpt-atlas"
    "codex-app"
    "lm-studio" # Local LLM runner
    "openclaw"
    "opencode-desktop"
    "typeless"

    # Development
    "cursor"
    "deskflow"
    "iterm2"
    "zed"
    "orbstack" # Docker/Linux VM alternative
    "xquartz" # X11 server
    "macfuse" # User-space filesystem

    # Browsers
    "firefox"
    "google-chrome"

    # Notes & Documents
    "typora" # Markdown editor
    "calibre" # E-book manager

    # Media
    "handbrake-app" # Video transcoder
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
    "appcleaner" # Remove apps and leftover files
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

    # Games
    "playcover-community" # Run iOS apps on Apple Silicon
  ];
}
