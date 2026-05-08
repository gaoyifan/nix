# zsh-vi-mode defers initialization to precmd hook and runs `bindkey -v`
# which resets the keymap. We must use zvm_after_init hook to ensure
# our custom keybindings survive the initialization.
function zvm_after_init() {
  function _codex_accept_buffer() {
    local prompt="$BUFFER"

    if [[ -z "${prompt//[[:space:]]/}" ]]; then
      zle redisplay
      return 0
    fi

    BUFFER="codex ${(qqq)prompt}"
    CURSOR=${#BUFFER}

    zle accept-line
  }
  zle -N _codex_accept_buffer

  # Option+Enter to run the current buffer as a Codex prompt
  bindkey '^[^M' _codex_accept_buffer

  # Esc+S to toggle sudo prefix (oh-my-zsh sudo plugin)
  bindkey "^[s" sudo-command-line

  # Esc+. to insert last word of last command (standard behaviour)
  bindkey -M viins '^[.' insert-last-word

  # Esc+B and Esc+F to move to prev/next word (standard behaviour)
  bindkey '^[b' backward-word
  bindkey '^[f' forward-word

  # Esc+D to kill word (standard behaviour)
  bindkey '^[d' kill-word

  # Emacs-style keybindings
  bindkey '^d' delete-char
  bindkey '^y' yank

  # Smart Up Arrow: use atuin if pressed within 1 second, otherwise use zsh history
  # Define the function and variable here, but bind after atuin initializes
  typeset -gi _atuin_last_up_time=0
  typeset -g _atuin_original_buffer=""
  typeset -gi _atuin_original_cursor=0

  function _atuin_smart_up() {
    local current_time=$EPOCHSECONDS
    local time_diff

    # Calculate time difference (handle first press)
    if (( _atuin_last_up_time == 0 )); then
      time_diff=2  # First press: use traditional history
      # Save the original buffer and cursor state before history search
      _atuin_original_buffer="$BUFFER"
      _atuin_original_cursor=$CURSOR
    else
      time_diff=$((current_time - _atuin_last_up_time))
    fi

    # If time difference <= 1 second, use atuin
    if (( time_diff <= 1 )); then
      # Restore the original buffer and cursor state before triggering atuin
      # This ensures atuin starts from the state before the first history search
      BUFFER="$_atuin_original_buffer"
      CURSOR=$_atuin_original_cursor

      # Try to call atuin's up arrow widget based on current keymap
      # Atuin creates different widgets for different keymap modes:
      # - atuin-up-search-viins: vim insert mode
      # - atuin-up-search-vicmd: vim normal mode
      # - atuin-up-search: emacs mode / fallback
      local atuin_widget
      # Check current keymap and try corresponding atuin widget
      if [[ "${KEYMAP:-}" == "vicmd" ]] && (( $+widgets[atuin-up-search-vicmd] )); then
        atuin_widget=atuin-up-search-vicmd
      elif [[ "${KEYMAP:-}" == "viins" ]] && (( $+widgets[atuin-up-search-viins] )); then
        atuin_widget=atuin-up-search-viins
      elif (( $+widgets[atuin-up-search] )); then
        atuin_widget=atuin-up-search
      fi

      if [[ -n "$atuin_widget" ]]; then
        zle $atuin_widget
      else
        # Fallback: use traditional history if atuin widget not available
        zle up-line-or-beginning-search
      fi
    else
      # Use traditional zsh history search
      # Save the current state before history search (for potential atuin trigger)
      _atuin_original_buffer="$BUFFER"
      _atuin_original_cursor=$CURSOR
      zle up-line-or-beginning-search
    fi

    _atuin_last_up_time=$current_time
  }
  zle -N _atuin_smart_up
  # Note: The actual binding is done in shell.nix via zvm_after_init_commands
  # to ensure it executes after atuin initializes
}
