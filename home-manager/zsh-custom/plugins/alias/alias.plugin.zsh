alias -g stat_='sort | uniq -c | sort -nk 1'

alias ls='ls -G --color=auto'
alias ncdu='ncdu -x --exclude "com~apple~CloudDocs" --exclude "Mobile Documents"'

setopt complete_aliases
compdef _fd fd
compdef _gh gh
compdef _mcat mcat
compdef _yazi yazi
compdef _files agy codex copilot cursor-agent difft
