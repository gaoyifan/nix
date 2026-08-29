#!/usr/bin/env bash
set -euo pipefail

is_codex_wrapper_script() {
  local script=$1
  [[ $script == "$HOME/.local/share/nix-lazy-apps/bin/codex" ||
    $script == "$HOME/.local/share/nix-lazy-apps/bin/codex-reindex" ||
    $script =~ ^/nix/store/[0-9a-z]{32}-codex$ ||
    $script =~ ^/nix/store/[0-9a-z]{32}-codex-reindex$ ||
    $script =~ ^/nix/store/[0-9a-z]{32}-codex-[^/]+/bin/codex$ ||
    $script =~ ^/nix/store/[0-9a-z]{32}-codex-reindex/bin/codex-reindex$ ]]
}

assert_no_codex_linux() {
  local uid pid exe name script reason found=0
  uid=$(id -u)

  while read -r pid; do
    [[ $pid == "$$" ]] && continue
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || continue
    exe=${exe% (deleted)}
    name=${exe##*/}
    reason=

    case "$name" in
    codex | .codex-wrapped | codex-code-mode-host)
      reason="Codex executable: $exe"
      ;;
    bash | sh | dash | zsh)
      script=$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | sed -n '2p')
      if is_codex_wrapper_script "$script"; then
        reason="Codex wrapper: $script"
      fi
      ;;
    uv | python | python3 | python3.*)
      if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null |
        grep -q '^CODEX_REINDEX_CODEX=' &&
        tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null |
        grep -Eq '(^|/)codex-reindex\.py$'; then
        reason=codex-reindex
      fi
      ;;
    esac

    if [[ -n $reason ]]; then
      printf 'active Codex: pid=%s %s\n' "$pid" "$reason" >&2
      found=1
    fi
  done < <(ps -eo uid=,pid= | awk -v uid="$uid" '$1 == uid { print $2 }')

  ((found == 0))
}

assert_no_codex_darwin() {
  local uid pid line arg0 arg1 rest name comm comm_name envline reason found=0
  uid=$(id -u)

  while read -r pid; do
    [[ $pid == "$$" ]] && continue
    line=$(ps -ww -p "$pid" -o command= 2>/dev/null) || continue
    [[ -n $line ]] || continue
    read -r arg0 arg1 rest <<<"$line"
    name=${arg0##*/}
    comm=$(ps -p "$pid" -o comm= 2>/dev/null) || comm=
    comm_name=${comm##*/}
    reason=

    case "$name:$comm_name" in
    codex:* | .codex-wrapped:* | codex-code-mode-host:* | \
      *:codex | *:.codex-wrapped | *:codex-code-mode-host)
      reason="Codex executable: $comm"
      ;;
    esac

    if [[ -z $reason ]] &&
      { is_codex_wrapper_script "$arg0" || is_codex_wrapper_script "$arg1"; }; then
      reason="Codex wrapper: $arg0 $arg1"
    fi

    case "$name" in
    uv | python | python3 | python3.*)
      if [[ -z $reason ]] &&
        [[ " $line " =~ [[:space:]][^[:space:]]*/codex-reindex\.py[[:space:]] ]] &&
        envline=$(ps eww -p "$pid" -o command= 2>/dev/null) &&
        [[ " $envline " == *" CODEX_REINDEX_CODEX="* ]]; then
        reason=codex-reindex
      fi
      ;;
    esac

    if [[ -n $reason ]]; then
      printf 'active Codex: pid=%s %s\n' "$pid" "$reason" >&2
      found=1
    fi
  done < <(ps -axo uid=,pid= | awk -v uid="$uid" '$1 == uid { print $2 }')

  ((found == 0))
}

assert_no_codex() {
  case "$(uname -s)" in
  Linux)
    assert_no_codex_linux
    ;;
  Darwin)
    assert_no_codex_darwin
    ;;
  *)
    echo "unsupported operating system: $(uname -s)" >&2
    return 1
    ;;
  esac
}

verify_deployed_wrapper() {
  local wrapper="$HOME/.local/share/nix-lazy-apps/bin/codex"

  if [[ ! -e $wrapper ]]; then
    echo "Codex wrapper is missing: $wrapper" >&2
    return 1
  fi
  if grep -q CODEX_SQLITE_HOME "$wrapper"; then
    echo "Codex wrapper still overrides CODEX_SQLITE_HOME: $wrapper" >&2
    return 1
  fi
}

migrate() {
  local legacy_dir="$HOME/.codex"
  local codex_home="$HOME/.syncd-dotfiles/.codex"
  local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/nix-lazy-apps/codex"
  local run_id state_dir preexisting_dir overwritten_dir source source_file relative target_file unexpected
  local -a sources existing_destination remaining rsync_options

  assert_no_codex || return 20
  verify_deployed_wrapper

  if [[ -L $legacy_dir || -L $codex_home ]]; then
    echo "refusing to migrate through a symlink: $legacy_dir or $codex_home" >&2
    return 1
  fi
  if [[ -e $codex_home && ! -d $codex_home ]]; then
    echo "CODEX_HOME path is not a directory: $codex_home" >&2
    return 1
  fi

  shopt -s nullglob
  sources=("$legacy_dir"/*.sqlite "$legacy_dir"/*.sqlite-*)
  for source in "${sources[@]}"; do
    if [[ ! -f $source || -L $source ]]; then
      echo "refusing unexpected SQLite entry: $source" >&2
      return 1
    fi
  done
  if [[ -e $legacy_dir/db-backups || -L $legacy_dir/db-backups ]]; then
    if [[ ! -d $legacy_dir/db-backups || -L $legacy_dir/db-backups ]]; then
      echo "refusing unexpected db-backups entry: $legacy_dir/db-backups" >&2
      return 1
    fi
    sources+=("$legacy_dir/db-backups")
  fi

  if ((${#sources[@]} > 0)); then
    if [[ ! -d $HOME/.syncd-dotfiles ]]; then
      echo "synchronized dotfiles root is missing: $HOME/.syncd-dotfiles" >&2
      return 1
    fi
    command -v rsync >/dev/null
    if [[ -d $legacy_dir/db-backups ]]; then
      unexpected=$(find "$legacy_dir/db-backups" ! -type f ! -type d -print -quit)
      if [[ -n $unexpected ]]; then
        echo "refusing unexpected entry in db-backups: $unexpected" >&2
        return 1
      fi
    fi
  fi

  if ((${#sources[@]} == 0)) && [[ ! -e $cache_file && ! -L $cache_file ]]; then
    echo "nothing to migrate or expire"
    return 0
  fi

  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  state_dir="$HOME/.local/state/codex-sqlite-home-migration/$run_id"
  preexisting_dir="$state_dir/preexisting-destination"
  overwritten_dir="$state_dir/destination-overwrites"
  install -d -m 700 "$state_dir" "$preexisting_dir" "$overwritten_dir"
  echo "recovery directory: $state_dir"

  if ((${#sources[@]} > 0)); then
    install -d -m 700 "$codex_home"
    existing_destination=("$codex_home"/*.sqlite "$codex_home"/*.sqlite-*)
    if [[ -e $codex_home/db-backups || -L $codex_home/db-backups ]]; then
      existing_destination+=("$codex_home/db-backups")
    fi
    for source in "${existing_destination[@]}"; do
      if [[ $source == "$codex_home/db-backups" ]]; then
        if [[ ! -d $source || -L $source ]]; then
          echo "refusing unexpected destination db-backups entry: $source" >&2
          return 1
        fi
      elif [[ ! -f $source || -L $source ]]; then
        echo "refusing unexpected destination SQLite entry: $source" >&2
        return 1
      fi
      echo "isolating preexisting destination data: ${source#"$codex_home"/}"
      mv -- "$source" "$preexisting_dir/"
    done

    rsync_options=(
      --archive
      --ignore-times
      --backup
      --backup-dir="$overwritten_dir"
      --relative
    )

    for source in "${sources[@]}"; do
      relative=${source#"$legacy_dir"/}
      echo "moving database data: $relative"
      rsync "${rsync_options[@]}" "$legacy_dir/./$relative" "$codex_home/"
    done

    for source in "${sources[@]}"; do
      if [[ -d $source ]]; then
        while IFS= read -r -d '' source_file; do
          relative=${source_file#"$legacy_dir"/}
          target_file="$codex_home/$relative"
          if [[ ! -f $target_file ]] || ! cmp -s "$source_file" "$target_file"; then
            echo "copied database backup failed verification: $relative" >&2
            return 1
          fi
        done < <(find "$source" -type f -print0)
      else
        relative=${source#"$legacy_dir"/}
        target_file="$codex_home/$relative"
        if [[ ! -f $target_file ]] || ! cmp -s "$source" "$target_file"; then
          echo "copied database file failed verification: $relative" >&2
          return 1
        fi
      fi
    done

    assert_no_codex || return 20

    for source in "${sources[@]}"; do
      if [[ -d $source ]]; then
        find "$source" -type f -delete
      else
        rm -- "$source"
      fi
    done
    if [[ -d $legacy_dir/db-backups ]]; then
      find "$legacy_dir/db-backups" -depth -type d -empty -delete
    fi

    remaining=("$legacy_dir"/*.sqlite "$legacy_dir"/*.sqlite-*)
    if ((${#remaining[@]} > 0)) || [[ -e $legacy_dir/db-backups || -L $legacy_dir/db-backups ]]; then
      echo "database data remains in legacy SQLite home" >&2
      return 1
    fi
  fi

  if [[ -e $cache_file || -L $cache_file ]]; then
    echo "expiring Codex CLI cache: $cache_file"
    mv "$cache_file" "$state_dir/codex-cli-cache"
  fi

  [[ ! -e $cache_file && ! -L $cache_file ]]
  echo "migration complete"
}

case "${1:-}" in
check)
  if assert_no_codex; then
    echo "no active Codex process"
  else
    exit 20
  fi
  ;;
migrate)
  migrate
  ;;
*)
  echo "usage: $0 check|migrate" >&2
  exit 2
  ;;
esac
