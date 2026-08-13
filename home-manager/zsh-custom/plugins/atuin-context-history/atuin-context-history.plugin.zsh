zmodload zsh/zle

typeset -ga _atuin_context_history_items=()
typeset -gi _atuin_context_history_active=0
typeset -gi _atuin_context_history_index=0
typeset -g _atuin_context_history_original_buffer=""
typeset -gi _atuin_context_history_original_cursor=0
typeset -g _atuin_context_history_pwd=""
typeset -g _atuin_context_history_last_buffer=""
typeset -gi _atuin_context_history_last_cursor=0

function _atuin_context_history_reset() {
  _atuin_context_history_items=()
  _atuin_context_history_active=0
  _atuin_context_history_index=0
}

# Register before zsh-vi-mode wraps zle-line-init. Registering afterward would
# add zsh-vi-mode's wrapper back into the hook list it calls and create a cycle.
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init _atuin_context_history_reset

function _atuin_context_history_matches_buffer() {
  (( _atuin_context_history_active )) \
    && [[ "$BUFFER" == "$_atuin_context_history_last_buffer" ]] \
    && (( CURSOR == _atuin_context_history_last_cursor )) \
    && [[ "$PWD" == "$_atuin_context_history_pwd" ]]
}

function _atuin_context_history_load() {
  local record
  local directory_output
  local global_output
  local -a directory_results=()
  local -a results=()
  local -A seen=()

  directory_output=$(
    ATUIN_QUERY="$LBUFFER" command atuin search \
      --cmd-only \
      --print0 \
      --filter-mode directory \
      --search-mode prefix \
      --author '$all-user' \
      --limit 200 \
      2>/dev/null
  )

  for record in "${(@0)directory_output}"; do
    if [[ -n "$record" ]]; then
      directory_results+=("$record")
    fi
  done

  if (( ${#directory_results} < 200 )); then
    for record in "${directory_results[@]}"; do
      seen[$record]=1
    done

    global_output=$(
      ATUIN_QUERY="$LBUFFER" command atuin search \
        --cmd-only \
        --print0 \
        --filter-mode global \
        --search-mode prefix \
        --author '$all-user' \
        --limit 200 \
        2>/dev/null
    )

    for record in "${(@0)global_output}"; do
      if [[ -n "$record" && -z ${seen[$record]+present} ]]; then
        results+=("$record")
      fi
    done

    while (( ${#results} > 200 - ${#directory_results} )); do
      shift results
    done
  fi

  results+=("${directory_results[@]}")

  _atuin_context_history_items=("${results[@]}")
  _atuin_context_history_active=1
  _atuin_context_history_index=$(( ${#results} + 1 ))
  _atuin_context_history_original_buffer="$BUFFER"
  _atuin_context_history_original_cursor=$CURSOR
  _atuin_context_history_pwd="$PWD"
  _atuin_context_history_last_buffer="$BUFFER"
  _atuin_context_history_last_cursor=$CURSOR

  if (( ${#results} == 0 )); then
    zle beep
    return 1
  fi
}

function _atuin_context_history_render() {
  if (( _atuin_context_history_index > ${#_atuin_context_history_items} )); then
    BUFFER="$_atuin_context_history_original_buffer"
    CURSOR=$_atuin_context_history_original_cursor
  else
    BUFFER="${_atuin_context_history_items[_atuin_context_history_index]}"
    CURSOR=${#BUFFER}
  fi

  _atuin_context_history_last_buffer="$BUFFER"
  _atuin_context_history_last_cursor=$CURSOR
}

function _atuin_context_history_up() {
  if (( _atuin_context_history_active )) && ! _atuin_context_history_matches_buffer; then
    _atuin_context_history_reset
  fi

  if [[ "$LBUFFER" == *$'\n'* ]]; then
    zle up-line
    if (( _atuin_context_history_active )); then
      _atuin_context_history_last_cursor=$CURSOR
    fi
    return 0
  fi

  if (( ! _atuin_context_history_active )); then
    _atuin_context_history_load || return
  fi

  if (( _atuin_context_history_index == 1 )); then
    zle beep
    return 0
  fi

  (( _atuin_context_history_index-- ))
  _atuin_context_history_render
}

function _atuin_context_history_down() {
  if (( _atuin_context_history_active )) && ! _atuin_context_history_matches_buffer; then
    _atuin_context_history_reset
  fi

  if [[ "$RBUFFER" == *$'\n'* ]]; then
    zle down-line
    if (( _atuin_context_history_active )); then
      _atuin_context_history_last_cursor=$CURSOR
    fi
    return 0
  fi

  if (( ! _atuin_context_history_active )); then
    zle down-line-or-history
    return 0
  fi

  if (( _atuin_context_history_index > ${#_atuin_context_history_items} )); then
    zle beep
    return 0
  fi

  (( _atuin_context_history_index++ ))
  _atuin_context_history_render
}

function _atuin_context_history_search() {
  _atuin_context_history_reset

  if [[ ${KEYMAP:-} == viins ]]; then
    zle atuin-search-viins
  else
    zle atuin-search
  fi
}

function _atuin_context_history_install() {
  zle -N _atuin_context_history_up
  zle -N _atuin_context_history_down
  zle -N _atuin_context_history_search

  bindkey -M vicmd '^[[A' _atuin_context_history_up
  bindkey -M vicmd '^[OA' _atuin_context_history_up
  bindkey -M vicmd '^[[B' _atuin_context_history_down
  bindkey -M vicmd '^[OB' _atuin_context_history_down
  bindkey -M viins '^[[A' _atuin_context_history_up
  bindkey -M viins '^[OA' _atuin_context_history_up
  bindkey -M viins '^[[B' _atuin_context_history_down
  bindkey -M viins '^[OB' _atuin_context_history_down
  bindkey -M emacs '^[[A' _atuin_context_history_up
  bindkey -M emacs '^[OA' _atuin_context_history_up
  bindkey -M emacs '^[[B' _atuin_context_history_down
  bindkey -M emacs '^[OB' _atuin_context_history_down

  bindkey -M emacs '^r' _atuin_context_history_search
  bindkey -M viins '^r' _atuin_context_history_search
  bindkey -M vicmd '/' _atuin_context_history_search
}
