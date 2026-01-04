# zsh-vi-mode defers initialization to precmd hook and runs `bindkey -v`
# which resets the keymap. We must use zvm_after_init hook to ensure
# our custom keybindings survive the initialization.
function zvm_after_init() {
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
}
