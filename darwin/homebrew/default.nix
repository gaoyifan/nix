{
  taps = [
    {
      name = "anomalyco/tap";
      trusted = true;
    }
  ];

  brews = [
    # Network diagnostics
    "iftop" # Display interface bandwidth usage
    "iproute2mac" # Linux 'ip' command wrapper for macOS
    "nali" # IP geolocation and CDN provider lookup
    "proxychains-ng" # Force apps through proxy

    # Development
    "git-lfs" # Git large file storage

    # System monitoring
    "mactop" # Apple Silicon Monitor Top written in Go Lang

    # AI Tools
    "anomalyco/tap/opencode"

    # Other tools
    "huggingface-cli" # Hugging Face CLI
    "ffmpeg" # Audio/video processing toolkit
    "yt-dlp" # Video downloader (YouTube, etc.)
  ];

  casks = [
    # Password & Security
    "1password"
    "electrum" # Bitcoin wallet

    # AI Tools
    "chatgpt"
    "grok-bot"
    "typeless"

    # Development
    "cursor"
    "iterm2"
    "xquartz" # X11 server
    "macfuse" # User-space filesystem

    # Communication
    "voov-meeting"

    # Browsers
    "firefox"
    "google-chrome"

    # Notes & Documents
    "typora" # Markdown editor
    "calibre" # E-book manager

    # Media
    "iina" # Modern video player
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
    "pearcleaner" # Remove apps and leftover files
    "balenaetcher" # USB/SD flasher
    "raspberry-pi-imager"

    # Fonts
    "font-inconsolata-for-powerline"
    "font-jetbrains-mono-nerd-font"

    # Input Method
    "squirrel-app" # Rime input method

    # Social
    "telegram"
  ];
}
