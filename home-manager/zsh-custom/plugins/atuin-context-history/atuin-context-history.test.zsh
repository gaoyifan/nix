#!/usr/bin/env zsh

set -euo pipefail

zmodload zsh/zpty
zmodload zsh/zselect

typeset -gr plugin_path="${0:A:h}/atuin-context-history.plugin.zsh"
typeset -gr atuin_path=$(command -v atuin)
typeset -gr zvm_plugin_path="$HOME/.zsh/plugins/vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
typeset -gr test_root=$(mktemp -d "${TMPDIR:-/tmp}/atuin-context-history.XXXXXX")
typeset -gr fake_bin="$test_root/bin"
typeset -gr test_log="$test_root/atuin-calls"
typeset -gr zdotdir="$test_root/zdotdir"

cleanup() {
  if zpty -t test_shell >/dev/null 2>&1; then
    zpty -d test_shell
  fi
  find "$test_root" -depth -delete
}
trap cleanup EXIT INT TERM

mkdir -p "$fake_bin" "$zdotdir" "$test_root/changed-directory"

print -rl -- \
  '#!/usr/bin/env zsh' \
  'if [[ $1 == init ]]; then' \
  '  exec "$ATUIN_TEST_REAL_ATUIN" "$@"' \
  'elif [[ $1 == uuid ]]; then' \
  '  print -r -- atuin-context-history-test' \
  '  exit 0' \
  'elif [[ $1 == history ]]; then' \
  '  [[ $2 == start ]] && print -r -- history-entry-id' \
  '  exit 0' \
  'fi' \
  'if [[ ${ATUIN_TEST_USE_REAL_SEARCH:-0} == 1 ]]; then' \
  '  exec "$ATUIN_TEST_REAL_ATUIN" "$@"' \
  'fi' \
  'for arg in "$@"; do' \
  '  if [[ $arg == -i ]]; then' \
  '    print -r -- "interactive|$ATUIN_QUERY|$PWD|$*" >> "$ATUIN_TEST_LOG"' \
  '    exit 0' \
  '  fi' \
  'done' \
  'print -r -- "batch|$ATUIN_QUERY|$PWD|$*" >> "$ATUIN_TEST_LOG"' \
  'if [[ "$ATUIN_QUERY" == none ]]; then' \
  '  exit 0' \
  'elif [[ "$ATUIN_QUERY" == multi ]]; then' \
  "  print -rn -- \$'print -r -- MULTI_ONE\\nprint -r -- MULTI_TWO\\0'" \
  'else' \
  "  print -rn -- \$'print -r -- OLDEST\\0print -r -- NEWEST\\0'" \
  'fi' \
  >"$fake_bin/atuin"
chmod +x "$fake_bin/atuin"

print -rl -- \
  'if [[ ${ATUIN_TEST_PREEXISTING_LINE_INIT:-0} == 1 ]]; then' \
  '  function _test_existing_line_init() { :; }' \
  '  zmodload zsh/zle' \
  '  autoload -Uz add-zle-hook-widget' \
  '  add-zle-hook-widget line-init _test_existing_line_init' \
  'fi' \
  'source "$ATUIN_TEST_PLUGIN"' \
  'typeset -ga zvm_after_init_commands' \
  'zvm_after_init_commands+=('\''eval "$(atuin init zsh --disable-up-arrow)"'\'')' \
  'zvm_after_init_commands+=('\''_atuin_context_history_install'\'')' \
  'ZVM_INIT_MODE=sourcing' \
  'source "$ATUIN_TEST_ZVM_PLUGIN"' \
  'function _test_chdir() { builtin cd "$ATUIN_TEST_CHDIR"; zle reset-prompt; }' \
  'zle -N _test_chdir' \
  'bindkey "^T" _test_chdir' \
  'bindkey -A "$ATUIN_TEST_KEYMAP" main' \
  "PROMPT='READY> '" \
  "RPROMPT=''" \
  >"$zdotdir/.zshrc"

start_shell() {
  local keymap=${1:-viins}
  local preexisting_line_init=${2:-0}
  : >"$test_log"
  zpty -b test_shell \
    "env PATH=${(q)fake_bin}:${(q)PATH} ATUIN_TEST_CHDIR=${(q)test_root}/changed-directory ATUIN_TEST_KEYMAP=${(q)keymap} ATUIN_TEST_LOG=${(q)test_log} ATUIN_TEST_PLUGIN=${(q)plugin_path} ATUIN_TEST_PREEXISTING_LINE_INIT=${(q)preexisting_line_init} ATUIN_TEST_REAL_ATUIN=${(q)atuin_path} ATUIN_TEST_ZVM_PLUGIN=${(q)zvm_plugin_path} ZDOTDIR=${(q)zdotdir} zsh -di"

  typeset -g start_output
  zpty -r test_shell start_output '*READY> *'
}

finish_shell() {
  zpty -w test_shell $'exit\n'
  zpty -d test_shell
}

assert_contains() {
  local actual=$1
  local expected=$2
  local message=$3

  if [[ $actual != *$expected* ]]; then
    print -ru2 -- "FAIL: $message"
    print -ru2 -- "Expected output to contain: $expected"
    print -ru2 -- "Actual output: ${(qqq)actual}"
    return 1
  fi
}

assert_not_contains() {
  local actual=$1
  local unexpected=$2
  local message=$3

  if [[ $actual == *$unexpected* ]]; then
    print -ru2 -- "FAIL: $message"
    print -ru2 -- "Unexpected output: $unexpected"
    print -ru2 -- "Actual output: ${(qqq)actual}"
    return 1
  fi
}

assert_equals() {
  local actual=$1
  local expected=$2
  local message=$3

  if [[ $actual != $expected ]]; then
    print -ru2 -- "FAIL: $message (expected $expected, got $actual)"
    return 1
  fi
}

batch_query_count() {
  awk -F '|' '$1 == "batch" { count++ } END { print count + 0 }' "$test_log"
}

wait_for_query_count() {
  local expected=$1
  local count

  for _ in {1..100}; do
    count=$(batch_query_count)
    (( count >= expected )) && return 0
    zselect -t 1 || true
  done

  print -ru2 -- "FAIL: timed out waiting for $expected Atuin queries"
  return 1
}

record_history() {
  local directory=$1
  local command=$2
  local id

  id=$(
    cd "$directory"
    ATUIN_LOG=error \
      ATUIN_CONFIG_DIR="$test_root/atuin-config" \
      ATUIN_DATA_DIR="$test_root/atuin-data" \
      ATUIN_SESSION=context-test \
      "$atuin_path" history start "$command"
  )

  ATUIN_LOG=error \
    ATUIN_CONFIG_DIR="$test_root/atuin-config" \
    ATUIN_DATA_DIR="$test_root/atuin-data" \
    ATUIN_SESSION=context-test \
    "$atuin_path" history end --exit 0 "$id"
}

query_history() {
  local directory=$1
  local filter_mode=$2
  local prefix=$3
  local record
  typeset -ga query_results=()

  while IFS= read -r -d $'\0' record; do
    query_results+=("$record")
  done < <(
    cd "$directory"
    ATUIN_LOG=error \
      ATUIN_CONFIG_DIR="$test_root/atuin-config" \
      ATUIN_DATA_DIR="$test_root/atuin-data" \
      ATUIN_SESSION=context-test \
      ATUIN_QUERY="$prefix" \
      "$atuin_path" search \
        --cmd-only \
        --print0 \
        --filter-mode "$filter_mode" \
        --search-mode prefix \
        --author '$all-user' \
        --limit 200
  )
}

test_consecutive_up_reuses_one_query() {
  start_shell

  zpty -w -n test_shell $'\e[A\e[A\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'OLDEST' 'two consecutive Up presses select the second result'
  assert_equals "$(batch_query_count)" 1 'two consecutive Up presses issue one Atuin query'

  finish_shell
}

test_preexisting_line_init_hook_does_not_recurse() {
  start_shell viins 1

  zpty -w -n test_shell $'\e[A'
  local output
  zpty -r test_shell output '*NEWEST*'

  assert_not_contains "$start_output$output" 'maximum nested function level reached' 'a pre-existing line-init hook does not recurse after zsh-vi-mode initialization'

  zpty -w -n test_shell $'\C-Cexit\n'
  zpty -d test_shell
}

test_emacs_application_cursor_keys_use_contextual_history() {
  start_shell emacs

  zpty -w -n test_shell $'\eOA\eOA\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'OLDEST' 'application cursor Up works in the emacs keymap'
  assert_equals "$(batch_query_count)" 1 'emacs application cursor keys reuse one Atuin query'

  finish_shell
}

test_vicmd_cursor_keys_use_contextual_history() {
  start_shell vicmd

  zpty -w -n test_shell $'\e[A\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'NEWEST' 'cursor Up works in the vicmd keymap'
  assert_equals "$(batch_query_count)" 1 'vicmd cursor keys issue one Atuin query'

  finish_shell
}

test_oldest_boundary_keeps_the_oldest_result() {
  start_shell

  zpty -w -n test_shell $'\e[A\e[A\e[A\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'OLDEST' 'Up at the oldest boundary keeps the oldest result'
  assert_equals "$(batch_query_count)" 1 'the oldest boundary does not issue another query'

  finish_shell
}

test_empty_query_result_preserves_the_original_buffer() {
  start_shell

  local output
  zpty -w -n test_shell $'none\e[A'
  wait_for_query_count 1
  zselect -t 20 || true
  zpty -w -n test_shell $'\e[A'
  zselect -t 100 || true
  assert_equals "$(batch_query_count)" 1 'consecutive Up presses reuse one empty query result'
  zpty -w -n test_shell $'\n'
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'none' 'an empty Atuin result leaves the original buffer intact'

  finish_shell
}

test_down_restores_original_buffer() {
  start_shell

  zpty -w -n test_shell $'print -r -- ORIGINAL\e[A\e[B\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'ORIGINAL' 'Down past the newest result restores the original buffer'
  assert_equals "$(batch_query_count)" 1 'restoring the original buffer reuses the active query'

  finish_shell
}

test_down_restores_original_cursor() {
  start_shell

  zpty -w -n test_shell $'print -r -- HEADTAIL\e[D\e[D\e[D\e[D\e[A\e[BMIDDLE\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'HEADMIDDLETAIL' 'Down restores the original cursor position as well as the buffer'
  assert_equals "$(batch_query_count)" 1 'restoring the original cursor reuses the active query'

  finish_shell
}

test_edit_starts_a_new_query_cycle() {
  start_shell

  zpty -w -n test_shell $'seed\e[A\C-Uprint -r -- EDITED\e[A\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'NEWEST' 'Up after editing uses the new query cycle result'
  assert_equals "$(batch_query_count)" 2 'editing the buffer starts exactly one new query cycle'
  assert_contains "$(tail -n 1 "$test_log")" 'print -r -- EDITED|' 'the new cycle uses the edited left buffer as its prefix'

  finish_shell
}

test_moving_cursor_starts_a_new_query_cycle() {
  start_shell

  zpty -w -n test_shell $'\e[A\e[D\e[D\e[D\e[D\e[D\e[D\e[A\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_equals "$(batch_query_count)" 2 'moving the cursor starts exactly one new query cycle'
  assert_contains "$(tail -n 1 "$test_log")" 'print -r -- |' 'the new cycle uses the new left buffer as its prefix'

  finish_shell
}

test_new_prompt_starts_a_new_query_cycle() {
  start_shell

  # Return to the original empty buffer before accepting it. The next prompt
  # has the same buffer, cursor, and PWD, so only the line-init boundary can
  # distinguish it from the previous cycle.
  local output
  zpty -w -n test_shell $'\e[A\e[B\n'
  zpty -r test_shell output '*READY> *'
  wait_for_query_count 1
  zpty -w -n test_shell $'\e[A\n'
  zpty -r test_shell output '*READY> *'
  wait_for_query_count 2

  assert_equals "$(batch_query_count)" 2 'a new prompt starts one new query cycle'

  finish_shell
}

test_ctrl_r_starts_a_new_query_cycle() {
  start_shell

  local output
  zpty -w -n test_shell $'\e[A'
  wait_for_query_count 1
  zpty -r test_shell output '*NEWEST*'

  zpty -w -n test_shell $'\C-R'
  for _ in {1..100}; do
    grep -q '^interactive|' "$test_log" && break
    zselect -t 1 || true
  done
  assert_equals "$(awk -F '|' '$1 == "interactive" { count++ } END { print count + 0 }' "$test_log")" 1 'Ctrl-R invokes Atuin interactive search once'

  zpty -w -n test_shell $'\e[A'
  zselect -t 100 || true
  assert_equals "$(batch_query_count)" 2 'leaving Ctrl-R invalidates the previous contextual query cycle'

  zpty -w -n test_shell $'\n'
  zpty -r test_shell output '*READY> *'
  finish_shell
}

test_changing_directory_starts_a_new_query_cycle() {
  start_shell

  local output
  zpty -w -n test_shell $'\e[A'
  zpty -r test_shell output '*NEWEST*'
  zpty -w -n test_shell $'\C-T'
  zpty -r test_shell output '*READY> *'
  zpty -w -n test_shell $'\e[A\n'
  zpty -r test_shell output '*READY> *'

  assert_equals "$(batch_query_count)" 2 'changing PWD starts exactly one new query cycle'
  assert_contains "$(tail -n 1 "$test_log")" "$test_root/changed-directory" 'the new cycle queries from the changed directory'

  finish_shell
}

test_multiline_result_moves_within_buffer_without_querying_again() {
  start_shell

  zpty -w -n test_shell $'multi\e[A\e[A\n'
  local output
  zpty -r test_shell output '*READY> *'

  assert_contains "$output" 'MULTI_ONE' 'a multiline history result preserves its first line'
  assert_contains "$output" 'MULTI_TWO' 'a multiline history result preserves its second line'
  assert_equals "$(batch_query_count)" 1 'moving up inside a multiline result does not issue another query'

  finish_shell
}

test_real_atuin_database_preserves_directory_and_workspace_context() {
  local workspace="$test_root/workspace"
  local subdirectory="$workspace/subdirectory"
  local elsewhere="$test_root/elsewhere"

  mkdir -p "$subdirectory" "$elsewhere" "$test_root/atuin-config" "$test_root/atuin-data"
  print -r -- 'workspaces = true' >"$test_root/atuin-config/config.toml"
  git -C "$workspace" init -q

  record_history "$workspace" 'cargo test --workspace'
  record_history "$subdirectory" 'cargo test subcrate'
  record_history "$elsewhere" 'cargo test elsewhere'
  record_history "$subdirectory" $'print -r -- MULTI_ONE\nprint -r -- MULTI_TWO'

  query_history "$subdirectory" directory cargo
  assert_equals "${(j:|:)query_results}" 'cargo test subcrate' 'directory mode returns only the exact current directory'

  query_history "$subdirectory" workspace cargo
  assert_equals "${(j:|:)query_results}" 'cargo test --workspace|cargo test subcrate' 'workspace mode returns root and child directory history'

  query_history "$elsewhere" workspace cargo
  assert_equals "${(j:|:)query_results}" 'cargo test elsewhere' 'workspace mode outside Git falls back to the exact directory'

  query_history "$subdirectory" workspace print
  assert_equals "${#query_results}" 1 'NUL output keeps a multiline command as one history item'
  assert_equals "$query_results[1]" $'print -r -- MULTI_ONE\nprint -r -- MULTI_TWO' 'a multiline command round-trips without modification'

  record_history "$workspace" 'print -r -- CONTEXT_ROOT'
  record_history "$subdirectory" 'print -r -- CONTEXT_SUBDIRECTORY'

  zpty -b test_shell \
    "cd ${(q)subdirectory} && exec env PATH=${(q)fake_bin}:${(q)PATH} ATUIN_CONFIG_DIR=${(q)test_root}/atuin-config ATUIN_DATA_DIR=${(q)test_root}/atuin-data ATUIN_SESSION=context-test ATUIN_TEST_KEYMAP=viins ATUIN_TEST_PLUGIN=${(q)plugin_path} ATUIN_TEST_REAL_ATUIN=${(q)atuin_path} ATUIN_TEST_USE_REAL_SEARCH=1 ATUIN_TEST_ZVM_PLUGIN=${(q)zvm_plugin_path} ZDOTDIR=${(q)zdotdir} zsh -di"
  local output
  zpty -r test_shell output '*READY> *'

  zpty -w -n test_shell $'print -r -- CONTEXT\e[A\n'
  zpty -r test_shell output '*READY> *'
  assert_contains "$output" 'CONTEXT_SUBDIRECTORY' 'the real ZLE widget selects the newest workspace match from Atuin'

  zpty -w -n test_shell $'print -r -- CONTEXT\e[A\e[A\n'
  zpty -r test_shell output '*READY> *'
  assert_contains "$output" 'CONTEXT_ROOT' 'the real ZLE widget reuses its batch to select the older workspace match'

  finish_shell
}

test_consecutive_up_reuses_one_query
print -r -- 'PASS: consecutive Up presses reuse one contextual Atuin query'
test_preexisting_line_init_hook_does_not_recurse
print -r -- 'PASS: pre-existing line-init hooks do not recurse'
test_emacs_application_cursor_keys_use_contextual_history
print -r -- 'PASS: emacs application cursor keys use contextual Atuin history'
test_vicmd_cursor_keys_use_contextual_history
print -r -- 'PASS: vicmd cursor keys use contextual Atuin history'
test_oldest_boundary_keeps_the_oldest_result
print -r -- 'PASS: the oldest boundary keeps its result without another query'
test_empty_query_result_preserves_the_original_buffer
print -r -- 'PASS: an empty Atuin result preserves the original buffer'
test_down_restores_original_buffer
print -r -- 'PASS: Down restores the original buffer without querying again'
test_down_restores_original_cursor
print -r -- 'PASS: Down restores the original cursor without querying again'
test_edit_starts_a_new_query_cycle
print -r -- 'PASS: editing starts one new contextual query cycle'
test_moving_cursor_starts_a_new_query_cycle
print -r -- 'PASS: moving the cursor starts one new contextual query cycle'
test_new_prompt_starts_a_new_query_cycle
print -r -- 'PASS: a new prompt starts one new contextual query cycle'
test_ctrl_r_starts_a_new_query_cycle
print -r -- 'PASS: Ctrl-R starts one new contextual query cycle'
test_changing_directory_starts_a_new_query_cycle
print -r -- 'PASS: changing directory starts one new contextual query cycle'
test_multiline_result_moves_within_buffer_without_querying_again
print -r -- 'PASS: multiline history remains intact and navigates without another query'
test_real_atuin_database_preserves_directory_and_workspace_context
print -r -- 'PASS: real Atuin DB queries preserve directory, workspace, prefix, and multiline semantics'
