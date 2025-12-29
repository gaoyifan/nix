{
  config,
  pkgs,
  ...
}: let
  iterm2-shell-integration = pkgs.fetchFromGitHub {
    owner = "gnachman";
    repo = "iTerm2-shell-integration";
    rev = "16a37c5f59243a68cd662a8cb70497cbcfaa10b2";
    hash = "sha256-vxGOr4jTAI0w4Y9Gz/1iEGT2YIq76DJiYIQ+vl4M7qA=";
  };
in {
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

  # Zsh Configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      strategy = [
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

    oh-my-zsh = {
      enable = true;
      custom = "${config.home.homeDirectory}/.oh-my-zsh/custom";
      # theme = "robbyrussell";

      plugins = [
        "git"
        "sudo"
        "tmux"
        "z"
        "history"
        "history-substring-search"
        "copyfile"
        "copypath"
        "docker-compose"
        "iterm2"
        # Custom plugins
        "alias"
        "docker"
        "ip"
        "keybind"
        "number-keypad"
        "package-manager"
      ];
    };

    envExtra = ''
      # Enable Homebrew
      if [ -e /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
    '';

    initContent = pkgs.lib.mkBefore ''
      # Enable zsh-completions
      fpath+=(${pkgs.zsh-completions}/share/zsh/site-functions)

      # Source Nix profile to ensure paths are correct (Autofix for non-NixOS)
      if [ -e ${config.home.homeDirectory}/.nix-profile/etc/profile.d/nix.sh ]; then . ${config.home.homeDirectory}/.nix-profile/etc/profile.d/nix.sh; fi

      # iTerm2 Shell Integration
      if [[ "$TERM_PROGRAM" == "iTerm.app" || ( -z "$TERM_PROGRAM" && ${iterm2-shell-integration}/utilities/it2check ) ]]; then
          source ${iterm2-shell-integration}/shell_integration/zsh
          path+=(${iterm2-shell-integration}/utilities)
      fi
    '';
  };

  # Extend session variables
  home.sessionVariables = {
    NH_FLAKE = "${config.home.homeDirectory}/nix/";

    # oh-my-zsh settings
    COMPLETION_WAITING_DOTS = "true";

    # Autosuggestion tweaks
    ZSH_AUTOSUGGEST_USE_ASYNC = "true";
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE = "20";
    ZSH_AUTOSUGGEST_MANUAL_REBIND = "true";
    KEYTIMEOUT = "1";
  };
}
