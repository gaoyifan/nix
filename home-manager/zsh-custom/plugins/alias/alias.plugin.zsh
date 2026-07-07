alias -g stat_='sort | uniq -c | sort -nk 1'

_nix_app() {
  local app="$1"
  shift

  command nix run \
    --option extra-substituters 'https://nix-cache.yfgao.net?priority=50' \
    --option extra-trusted-public-keys nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4= \
    "github:gaoyifan/nix#$app" -- "$@"
}

alias agy='_nix_app agy'
alias copilot='_nix_app copilot --yolo'
alias codex='_nix_app codex'
alias cursor-agent='_nix_app cursor-agent'
alias difft='_nix_app difftastic'
alias fd='_nix_app fd'
alias gh='_nix_app gh'
alias mcat='_nix_app mcat'
alias yazi='_nix_app yazi'
alias ls='ls -G --color=auto'
alias ncdu='ncdu -x --exclude "com~apple~CloudDocs" --exclude "Mobile Documents"'
