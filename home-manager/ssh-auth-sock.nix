{
  lib,
  pkgs,
  ...
}: {
  programs.zsh.initContent = lib.mkAfter ''
    # Keep SSH_AUTH_SOCK fresh after reattaching long-lived tmux sessions.
    # Also publish it at the stable path used by Codex.
    zmodload -F zsh/net/socket b:zsocket
    typeset -g _ssh_auth_sock_stable="$HOME/.ssh/agent.sock"
    typeset -g _ssh_auth_sock_1password="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    typeset -g _ssh_auth_sock_last_refresh=0

    _ssh_auth_sock_connectable() {
        emulate -L zsh
        local sock="$1"
        local REPLY

        zsocket "$sock" 2>/dev/null || return 1
        exec {REPLY}>&-
    }

    _ssh_auth_sock_healthy() {
        emulate -L zsh
        local sock="$1"

        _ssh_auth_sock_connectable "$sock" || return 1

        SSH_AUTH_SOCK="$sock" ${pkgs.coreutils}/bin/timeout 1 \
            ${pkgs.openssh}/bin/ssh-add -l >/dev/null 2>&1
        case "$?" in
            0|1) return 0 ;;
            *) return 1 ;;
        esac
    }

    _ssh_auth_sock_publish() {
        emulate -L zsh
        local sock="$1"
        local next

        [[ -n "$_ssh_auth_sock_stable" && "$sock" != "$_ssh_auth_sock_stable" ]] || return 0
        [[ "$_ssh_auth_sock_stable" -ef "$sock" ]] && return 0

        ${pkgs.coreutils}/bin/mkdir -p -m 700 -- "$HOME/.ssh"
        next="$_ssh_auth_sock_stable.$$.new"
        ${pkgs.coreutils}/bin/ln -sfn -- "$sock" "$next" &&
            ${pkgs.coreutils}/bin/mv -f -- "$next" "$_ssh_auth_sock_stable"
    }

    _ssh_auth_sock_probe() {
        emulate -L zsh

        local -a candidates
        local sock current="''${1:-''${SSH_AUTH_SOCK:-}}"
        local current_checked=0

        if [[ "$current" == "$_ssh_auth_sock_stable" ]]; then
            current="''${current:A}"
        fi

        case "$current" in
            ""|"$_ssh_auth_sock_stable"|"$_ssh_auth_sock_1password"|/private/tmp/com.apple.launchd.*/Listeners|/private/var/run/com.apple.launchd.*/Listeners|/private/var/folders/*/*/*/com.apple.launchd.*/Listeners|/var/run/com.apple.launchd.*/Listeners|/var/folders/*/*/*/com.apple.launchd.*/Listeners) ;;
            *)
                current_checked=1
                if _ssh_auth_sock_healthy "$current"; then
                    print -r -- "$current"
                    return 0
                fi
                ;;
        esac

        candidates+=(
            /tmp/ssh-*/agent.*(N=)
            /tmp/tsshd-*/agent.*(N=)
            /private/tmp/ssh-*/agent.*(N=)
            /private/tmp/tsshd-*/agent.*(N=)
            /var/folders/*/*/*/ssh-*/agent.*(N=)
            /var/folders/*/*/*/tsshd-*/agent.*(N=)
            "$_ssh_auth_sock_1password"
            /private/tmp/com.apple.launchd.*/Listeners(N=)
            /var/run/com.apple.launchd.*/Listeners(N=)
            /var/folders/*/*/*/com.apple.launchd.*/Listeners(N=)
        )

        for sock in "''${candidates[@]}"; do
            (( current_checked )) && [[ "$sock" == "$current" ]] && continue
            _ssh_auth_sock_healthy "$sock" || continue
            print -r -- "$sock"
            return 0
        done

        return 1
    }

    _ssh_auth_sock_refresh_async() {
        emulate -L zsh
        local sock current="''${1:-''${SSH_AUTH_SOCK:-}}"

        if (( _ssh_auth_sock_last_refresh > 0 && SECONDS - _ssh_auth_sock_last_refresh < 5 )); then
            return 0
        fi

        _ssh_auth_sock_last_refresh="$SECONDS"
        {
            sock="$(_ssh_auth_sock_probe "$current")" || return
            _ssh_auth_sock_publish "$sock"
        } &!
    }

    refresh-ssh-auth-sock() {
        local sock
        if ! sock="$(_ssh_auth_sock_probe)"; then
            return 1
        fi

        _ssh_auth_sock_publish "$sock"
        export SSH_AUTH_SOCK="$_ssh_auth_sock_stable"
        printf 'SSH_AUTH_SOCK=%s\n' "$SSH_AUTH_SOCK"
    }

    fix-ssh-auth-sock() {
        refresh-ssh-auth-sock "$@"
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _ssh_auth_sock_refresh_async

    _ssh_auth_sock_publish "''${SSH_AUTH_SOCK:-}"
    _ssh_auth_sock_refresh_async "''${SSH_AUTH_SOCK:-}"
    export SSH_AUTH_SOCK="$_ssh_auth_sock_stable"
  '';
}
