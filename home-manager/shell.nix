{
  config,
  pkgs,
  lib,
  ...
}: let
  hasAtuinSecrets = config.services.secrets.atuin.available;
  cliApps = import ../cli-apps.nix {inherit lib;};
  dynamicCli = cliApps.mkHomeManager pkgs;
  zsh-codex-mode = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "zsh-codex-mode";
    rev = "22d620d6b0c366497ed25d0a2021dd9252736962";
    hash = "sha256-K/FqZSKOx5llsdzC5eI6nwLJZB99t6yDmSQGnQse/74=";
  };
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
    dynamicCli.completions
    zsh-completions
    jq
  ];

  home.file = dynamicCli.wrapperFiles;

  programs.powerline-go.enable = true;

  programs.atuin = {
    enable = true;
    forceOverwriteSettings = true;
    settings =
      {
        workspaces = true;
        filter_mode_shell_up_key_binding = "workspace";
        inline_height = 9;
        enter_accept = true;
      }
      // lib.optionalAttrs hasAtuinSecrets {
        sync_address = "http://atuin-server.ts.gaof.net";
        auto_sync = true;
        sync_frequency = "5m";
        sync = {
          records = true;
        };
      };
    # zsh-vi-mode initializes vi keymaps lazily and runs `bindkey -v`, which can
    # clobber bindings set by atuin's default zsh integration. We initialize atuin
    # via zsh-vi-mode's `after_init` hook instead (see `programs.zsh.initContent`).
    enableZshIntegration = false;
  };

  # Atuin Login Automation (failures are non-blocking to avoid breaking deployment)
  home.activation.atuinLogin = lib.hm.dag.entryAfter ["linkGeneration"] ''
    if [ "${lib.boolToString hasAtuinSecrets}" = "true" ] \
      && [ -f "${config.services.secrets.atuin.passwordFile}" ] \
      && [ -f "${config.services.secrets.atuin.keyFile}" ]; then
      if ! ${pkgs.atuin}/bin/atuin status 2>/dev/null | grep -q "Username: ${config.home.username}"; then
        echo "Atuin not logged in. Attempting automated login..."
        ${pkgs.coreutils}/bin/timeout 10s ${pkgs.atuin}/bin/atuin login -u ${config.home.username} \
          -p "$(<"${config.services.secrets.atuin.passwordFile}")" \
          -k "$(<"${config.services.secrets.atuin.keyFile}")" || echo "Atuin login failed (non-blocking)"
      else
        echo "Atuin is already logged in."
      fi
    fi
  '';

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    stdlib = ''
      layout_uv() {
          if [[ -d ".venv" ]]; then
              VIRTUAL_ENV="$(pwd)/.venv"
          fi

          if [[ -z $VIRTUAL_ENV || ! -d $VIRTUAL_ENV ]]; then
              log_status "No virtual environment exists. Executing \`uv venv\` to create one."
              uv venv
              VIRTUAL_ENV="$(pwd)/.venv"
          fi

          if [ -d ".venv/bin" ]; then
              PATH_add .venv/bin
          elif [ -d ".venv/Scripts" ]; then
              PATH_add .venv/Scripts
          fi
          export UV_ACTIVE=1  # or VENV_ACTIVE=1
          export VIRTUAL_ENV
      }
    '';
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.tmux = {
    enable = true;
    mouse = true;
    historyLimit = 10000;
    terminal = "xterm-256color";
    extraConfig = ''
      set -as terminal-features ",xterm-256color:RGB"
      set -g window-status-current-style ""
      set -g status-right "#{?window_bigger,[#{window_offset_x},#{window_offset_y}],}"
      set -g set-titles on
      set -g set-titles-string "(T) #{pane_title}"
      set -g window-status-format "#[fg=white,bold]#I.#[default]#{=16:pane_title}#F"
      set -g window-status-current-format "#[fg=white,bold]#I.#[default,bg=white]#{=16:pane_title}#[default]#F"
    '';
  };

  # Zsh Configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      strategy = [
        "match_prev_cmd"
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
    localVariables.ZSH_CODEX_MODE_MCP = "disabled";

    plugins = [
      {
        name = "zsh-codex-mode";
        src = zsh-codex-mode;
        file = "zsh-codex-mode.plugin.zsh";
      }
      {
        name = "vi-mode";
        src = pkgs.zsh-vi-mode;
        file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
      }
    ];

    oh-my-zsh = {
      enable = true;
      custom = "${./zsh-custom}";

      plugins = [
        # Official plugins
        "git"
        "sudo"
        "tmux"
        "copyfile"
        "copypath"
        "dotenv"
        # Custom plugins
        "alias"
        "docker-extras"
        "ip"
        "keybind"
        "package-manager"
      ];
    };

    envExtra = ''
      # Enable Homebrew (only if not already in PATH to preserve direnv precedence in subshells)
      if [ -e /opt/homebrew/bin/brew ] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -e /home/linuxbrew/.linuxbrew/bin/brew ] && [[ ":$PATH:" != *":/home/linuxbrew/.linuxbrew/bin:"* ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
      fi

      # Keep lazy wrappers behind regular user and platform paths so existing
      # same-name tools win by normal PATH lookup.
      if [[ ":$PATH:" != *":${config.home.homeDirectory}/${dynamicCli.relBinDir}:"* ]]; then
        export PATH="''${PATH:+$PATH:}${config.home.homeDirectory}/${dynamicCli.relBinDir}"
      fi
    '';

    profileExtra = ''
      # Prefer the 1Password SSH agent over macOS's transient launchd socket.
      case "''${SSH_AUTH_SOCK:-}" in
        ""|/private/tmp/com.apple.launchd.*/Listeners|/var/run/com.apple.launchd.*/Listeners)
          export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
          ;;
      esac
    '';

    initContent = pkgs.lib.mkMerge [
      (pkgs.lib.mkBefore ''
        ${lib.optionalString pkgs.stdenv.isDarwin ''
          # Keep the prompt hostname independent of DHCP and reverse DNS.
          HOST="$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || hostname -s)"
        ''}

        # Nix single-user mode on Linux
        if [ -e ~/.nix-profile/etc/profile.d/nix.sh ]; then
          source ~/.nix-profile/etc/profile.d/nix.sh
        fi
      '')
      (pkgs.lib.mkAfter ''
        # Atuin: disable Up Arrow binding, and init after zsh-vi-mode sets keymaps.
        typeset -ga zvm_after_init_commands
        zvm_after_init_commands+=('eval "$(atuin init zsh)"')
        # Override atuin's up arrow binding with smart binding after atuin initializes
        # The _atuin_smart_up function is defined in keybind plugin's zvm_after_init
        zvm_after_init_commands+=('bindkey "^[[A" _atuin_smart_up')
        zvm_after_init_commands+=('bindkey -M vicmd "^[[A" _atuin_smart_up')
        zvm_after_init_commands+=('bindkey -M viins "^[[A" _atuin_smart_up')
        zvm_after_init_commands+=('bindkey -M emacs "^[[A" _atuin_smart_up')
      '')
      (pkgs.lib.mkAfter ''
        # iTerm2 Shell Integration
        if [[ "$TERM_PROGRAM" == "iTerm.app" || "$TMUX" == *lazyssh* || ( -z "$TERM_PROGRAM" && ${iterm2-shell-integration}/utilities/it2check ) ]]; then
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
