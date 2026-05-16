{pkgs, ...}: {
  programs.zsh.initContent = pkgs.lib.mkAfter ''
    # Keep SSH_AUTH_SOCK fresh after reattaching long-lived tmux sessions.
    zmodload -F zsh/stat b:zstat 2>/dev/null || true
    typeset -g _ssh_auth_sock_cache="''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}/ssh-auth-sock.$UID"
    typeset -g _ssh_auth_sock_refresh_pid=0
    typeset -g _ssh_auth_sock_last_refresh=0

    _ssh_auth_sock_probe() {
        emulate -L zsh
        setopt null_glob

        local -a candidates stat_info
        local sock best_sock mtime best_mtime=0

        if [[ -n "''${SSH_AUTH_SOCK:-}" ]]; then
            candidates+=("''${SSH_AUTH_SOCK:h}"/*(N=))
        fi

        candidates+=(
            "$HOME"/.ssh/agent/*(N=)
            /tmp/ssh-*/agent.*(N=)
            /private/tmp/ssh-*/agent.*(N=)
            /private/tmp/com.apple.launchd.*/Listeners(N=)
            /var/folders/*/*/*/ssh-*/agent.*(N=)
            /var/folders/*/*/*/com.apple.launchd.*/Listeners(N=)
            /run/user/$UID/agent.*(N=)
            /run/user/$UID/*ssh-agent*(N=)
            /run/user/$UID/openssh_agent(N=)
        )

        for sock in "''${candidates[@]}"; do
            [[ -S "$sock" ]] || continue

            zstat -A stat_info +mtime -- "$sock" 2>/dev/null || continue
            mtime="$stat_info[1]"
            if (( mtime > best_mtime )); then
                best_mtime="$mtime"
                best_sock="$sock"
            fi
        done

        [[ -n "''${best_sock:-}" ]] && print -r -- "$best_sock"
    }

    _ssh_auth_sock_apply_cache() {
        emulate -L zsh
        local sock

        [[ -r "$_ssh_auth_sock_cache" ]] || return 0
        IFS= read -r sock < "$_ssh_auth_sock_cache" || return 0
        [[ -n "$sock" && "$sock" != "''${SSH_AUTH_SOCK:-}" && -S "$sock" ]] || return 0

        export SSH_AUTH_SOCK="$sock"
    }

    _ssh_auth_sock_refresh_async() {
        emulate -L zsh
        local sock

        if (( _ssh_auth_sock_refresh_pid > 0 )) && kill -0 "$_ssh_auth_sock_refresh_pid" 2>/dev/null; then
            return 0
        fi

        if (( _ssh_auth_sock_last_refresh > 0 && SECONDS - _ssh_auth_sock_last_refresh < 5 )); then
            return 0
        fi

        _ssh_auth_sock_last_refresh="$SECONDS"
        {
            sock="$(_ssh_auth_sock_probe)" || return
            print -r -- "$sock" >| "$_ssh_auth_sock_cache"
        } &!
        _ssh_auth_sock_refresh_pid="$!"
    }

    _ssh_auth_sock_precmd() {
        _ssh_auth_sock_apply_cache
        _ssh_auth_sock_refresh_async
    }

    _ssh_auth_sock_preexec() {
        _ssh_auth_sock_apply_cache
    }

    refresh-ssh-auth-sock() {
        local sock
        if ! sock="$(_ssh_auth_sock_probe)"; then
            return 1
        fi

        export SSH_AUTH_SOCK="$sock"
        print -r -- "$sock" >| "$_ssh_auth_sock_cache"
        printf 'SSH_AUTH_SOCK=%s\n' "$SSH_AUTH_SOCK"
    }

    fix-ssh-auth-sock() {
        refresh-ssh-auth-sock "$@"
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _ssh_auth_sock_precmd
    add-zsh-hook preexec _ssh_auth_sock_preexec

    _ssh_auth_sock_refresh_async
  '';
}
