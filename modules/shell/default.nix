{
  config,
  pkgs,
  ...
}:
let
  iterm2-shell-integration = pkgs.fetchFromGitHub {
    owner = "gnachman";
    repo = "iTerm2-shell-integration";
    rev = "16a37c5f59243a68cd662a8cb70497cbcfaa10b2";
    hash = "sha256-vxGOr4jTAI0w4Y9Gz/1iEGT2YIq76DJiYIQ+vl4M7qA=";
  };
in
{
  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # Zsh completions
    zsh-completions
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # Copy/Link custom zsh plugins and theme
    ".oh-my-zsh/custom/plugins".source = ./zsh-custom;
  };

  programs.powerline-go.enable = true;

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # Zsh Configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      strategy = [
        "match_prev_cmd"
        "history"
        "completion"
      ];
    };

    # History configuration
    history = {
      size = 120000;
      save = 100000;
      expireDuplicatesFirst = true;
      ignoreDups = true;
      share = true; # This implies INC_APPEND_HISTORY usually
    };

    syntaxHighlighting.enable = true;

    plugins = [
      {
        name = "vi-mode";
        src = pkgs.zsh-vi-mode;
        file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
      }
    ];

    oh-my-zsh = {
      enable = true;
      custom = "${config.home.homeDirectory}/.oh-my-zsh/custom";

      plugins = [
        "git"
        "sudo"
        "tmux"
        "copyfile"
        "copypath"
        "iterm2"
        "dotenv"
        # Custom plugins
        "alias"
        "docker"
        "ip"
        "keybind"
        "package-manager"
      ];
    };

    envExtra = ''
      # Enable Homebrew
      if [ -e /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
    '';

    initContent = pkgs.lib.mkMerge [
      (pkgs.lib.mkBefore ''
        # Nix single-user mode on Linux
        if [ -e ~/.nix-profile/etc/profile.d/nix-daemon.sh ]; then
          source ~/.nix-profile/etc/profile.d/nix-daemon.sh
        fi
      '')
      (pkgs.lib.mkAfter ''
        # iTerm2 Shell Integration
        if [[ "$TERM_PROGRAM" == "iTerm.app" || ( -z "$TERM_PROGRAM" && ${iterm2-shell-integration}/utilities/it2check ) ]]; then
            source ${iterm2-shell-integration}/shell_integration/zsh
            path+=(${iterm2-shell-integration}/utilities)
        fi
      '')
    ];
  };

  # Extend session variables
  home.sessionVariables = {
    # oh-my-zsh settings
    COMPLETION_WAITING_DOTS = "true";

    # Autosuggestion tweaks
    ZSH_AUTOSUGGEST_USE_ASYNC = "true";
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE = "20";
    ZSH_AUTOSUGGEST_MANUAL_REBIND = "true";
    KEYTIMEOUT = "1";
  };
}
