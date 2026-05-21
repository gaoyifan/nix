alias -g stat_='sort | uniq -c | sort -nk 1'

_yf_nix_run_cli() {
  local app="$1"
  shift

  command nix run \
    --option extra-substituters https://nix-cache.yfgao.net \
    --option extra-trusted-public-keys nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4= \
    "github:gaoyifan/nix#$app" -- "$@"
}

alias agy='_yf_nix_run_cli agy'
alias copilot='_yf_nix_run_cli copilot'
alias codex='_yf_nix_run_cli codex'
alias cursor-agent='_yf_nix_run_cli cursor-agent'
alias ls='ls -G --color=auto'
alias ncdu='ncdu -x --exclude "com~apple~CloudDocs" --exclude "Mobile Documents"'
