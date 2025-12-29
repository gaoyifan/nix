{ config, pkgs, ... }:

let
  # Define custom plugins that need to be sourced manually or added to fpath
  # Since we copied them to ./zsh-custom, we can iterate over them or just refer to them
  # However, oh-my-zsh module in home-manager usually takes plugins from nixpkgs or specific paths
  # A simpler way for custom plugins in a local directory is to source them in extraConfig or initExtra

  # Vim configuration
  vimConfig = pkgs.fetchFromGitHub {
    owner = "amix";
    repo = "vimrc";
    rev = "master";
    sha256 = "sha256-g1appWgZlE27Rm8gorGp9B1c6UvGhg1bESgHk8umJ8g=";
  };
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "yifan";
  home.homeDirectory = "/home/yifan";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # Core utilities
    tmux
    curl
    wget
    delta # git pager
    
    # Custom tools mentioned in zsh plugins (dependencies)
    # docker # Managed by system? Adding just in case or assume system docker
    # python3 # for some plugins
    
    # Custom tools
    tree
    
    # Zsh completions
    zsh-completions
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # Link the ultimate vimrc
    ".vim_runtime".source = vimConfig;
    
    # Copy/Link custom zsh plugins and theme
    ".oh-my-zsh/custom/plugins".source = ./zsh-custom;
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. If you don't want to manage your shell through Home
  # Manager then you have to manually source 'hm-session-vars.sh' located at
  # either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/yifan/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "vim";
  };
  
  # Git Configuration
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Yifan Gao";
        email = "git@yfgao.com";
      };
      push = { autoSetupRemote = true; };
      core = { pager = "delta"; };
      interactive = { diffFilter = "delta --color-only"; };
      delta = { navigate = true; };
      merge = { conflictstyle = "diff3"; };
      diff = { colorMoved = "default"; };
      "filter \"lfs\"" = {
        clean = "git-lfs clean -- %f";
        smudge = "git-lfs smudge -- %f";
        process = "git-lfs filter-process";
        required = true;
      };
    };
  };

  programs.powerline-go = {
    enable = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };

  # Zsh Configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true; 
    autosuggestion = {
      enable = true;
      strategy = [ "history" "completion" ];
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
        "alias" "docker" "ip" "iterm2-integration" "keybind" 
        "number-keypad" "package-manager" 
      ];
    };

    # Init Extra for things not covered by module options
    initContent = ''
      # Custom Settings from .zshrc
      export UPDATE_ZSH_DAYS=7
      COMPLETION_WAITING_DOTS="true"
      DISABLE_UNTRACKED_FILES_DIRTY="true"
      
      # Autosuggestion tweaks
      ZSH_AUTOSUGGEST_USE_ASYNC=true
      ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
      ZSH_AUTOSUGGEST_MANUAL_REBIND=true
      
      export KEYTIMEOUT=1
      
      # Fix bindings
      _zsh_autosuggest_bind_widgets
    '';
  };

  # Vim configuration
  programs.vim = {
    enable = true;
    extraConfig = ''
      set runtimepath+=~/.vim_runtime

      source ~/.vim_runtime/vimrcs/basic.vim
      source ~/.vim_runtime/vimrcs/filetypes.vim
      source ~/.vim_runtime/vimrcs/plugins_config.vim
      source ~/.vim_runtime/vimrcs/extended.vim
      try
        source ~/.vim_runtime/my_configs.vim
      catch
      endtry
    '';
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
