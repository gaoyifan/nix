# Nix profile path
nix_profile := "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
nix_bin_dir := "/nix/var/nix/profiles/default/bin"
submodule_path := "secrets/files"
home_manager_backup_extension := "backup-$(date +%Y%m%d-%H%M%S)"
deploy_rebuild_substituters := "https://mirrors.ustc.edu.cn/nix-channels/store https://mirror.sjtu.edu.cn/nix-channels/store https://nix-cache.yfgao.net?priority=50 https://cache.nixos.org?priority=100"
self_just := quote(just_executable()) + " --justfile " + quote(justfile()) + " --working-directory " + quote(justfile_directory()) + " --quiet"

# Default recipe: pulls the latest code, then applies the appropriate configuration
default:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Pulling latest repository changes..."
    old_head="$(git rev-parse HEAD)"
    if ! git pull --recurse-submodules; then
        if [ -e /etc/NIXOS ]; then
            echo "git pull failed on NixOS; continuing with the current worktree." >&2
        else
            exit 1
        fi
    elif [ "$old_head" != "$(git rev-parse HEAD)" ]; then
        echo "Repository updated; restarting just with the latest justfile..."
        exec {{ self_just }}
    fi
    {{ self_just }} ensure-nix
    {{ self_just }} trust-flake-config
    source <({{ self_just }} _emit_nix_env)
    if [ "$(uname)" = "Darwin" ]; then
        echo "Detected macOS, applying nix-darwin configuration..."
        {{ self_just }} darwin
    else
        if [ -e /etc/NIXOS ]; then
            echo "Detected NixOS, applying NixOS configuration..."
            {{ self_just }} nixos
        else
            echo "Detected Linux, applying home-manager configuration..."
            {{ self_just }} home
            echo "Detected non-NixOS Linux, applying system-manager configuration..."
            {{ self_just }} system
        fi
    fi

# Ensure nix is installed before proceeding
ensure-nix:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v nix >/dev/null 2>&1 && [ ! -f "{{ nix_profile }}" ]; then
        echo "Nix not found, installing..."
        just install-nix
    else
        echo "Nix is already installed."
    fi

# Trust this flake's substituter settings for future runs.
[group('setup')]
trust-flake-config:
    #!/usr/bin/env bash
    set -euo pipefail
    local_hostname="$(hostname -s)"
    secrets_dir="secrets/files-example"
    if [ -f "{{ submodule_path }}/.gitkeep" ] || [ -f "{{ submodule_path }}/.git" ]; then
        secrets_dir="{{ submodule_path }}"
    fi
    private_substituters="$(
        INTERNAL_SUBSTITUTER_HOSTNAME="$local_hostname" \
            nix eval --impure --raw --file "$secrets_dir/nixos/internal-substituters.nix" \
                --apply 'configure: builtins.concatStringsSep " " (configure { hostname = builtins.getEnv "INTERNAL_SUBSTITUTER_HOSTNAME"; }).substituters'
    )"
    mkdir -p ~/.local/share/nix
    printf '%s\n' '{"substituters":{"https://cache.nixos.org https://nix-cache.yfgao.net?priority=50":true},"trusted-public-keys":{"cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4=":true}}' > ~/.local/share/nix/trusted-settings.json
    if [ -w /etc/nix/nix.custom.conf ] || command -v sudo >/dev/null 2>&1; then
        additions=()
        nix_config_changed=false
        if ! grep -q 'nix-cache.yfgao.net' /etc/nix/nix.custom.conf 2>/dev/null; then
            additions+=(
                ''
                '# yifan nix binary cache'
                'extra-substituters = https://nix-cache.yfgao.net?priority=50'
                'extra-trusted-public-keys = nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4='
            )
        fi
        private_cache_current=false
        if grep -Fqx '# private Nix binary cache' /etc/nix/nix.custom.conf 2>/dev/null; then
            if [ -n "$private_substituters" ] \
                && grep -Fqx "extra-substituters = $private_substituters" /etc/nix/nix.custom.conf; then
                private_cache_current=true
            else
                filtered_config="$(mktemp)"
                sudo awk '
                    skip_private_cache { skip_private_cache = 0; next }
                    $0 == "# private Nix binary cache" { skip_private_cache = 1; next }
                    { print }
                ' /etc/nix/nix.custom.conf > "$filtered_config"
                sudo tee /etc/nix/nix.custom.conf < "$filtered_config" >/dev/null
                rm "$filtered_config"
                nix_config_changed=true
            fi
        fi
        if [ -n "$private_substituters" ] && ! "$private_cache_current"; then
            additions+=(
                ''
                '# private Nix binary cache'
                "extra-substituters = $private_substituters"
            )
        fi
        if [ "${#additions[@]}" -gt 0 ]; then
            printf '%s\n' "${additions[@]}" | sudo tee -a /etc/nix/nix.custom.conf >/dev/null
            nix_config_changed=true
        fi
        if "$nix_config_changed"; then
            if [ "$(uname)" = "Darwin" ]; then
                sudo launchctl kickstart -k system/systems.determinate.nix-daemon || true
            else
                sudo systemctl restart nix-daemon 2>/dev/null || true
            fi
        fi
    fi
    echo "Trusted flake substituter settings are up to date."

# Install nix using Determinate Systems installer
[group('setup')]
install-nix:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing Nix via Determinate Systems installer..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
        sh -s -- install --no-confirm --diagnostic-endpoint=""
    echo "Configuring trusted-users for flake substituters..."
    echo "extra-trusted-users = $(whoami)" | sudo tee -a /etc/nix/nix.custom.conf >/dev/null
    if [ "$(uname)" = "Darwin" ]; then
        sudo launchctl kickstart -k system/systems.determinate.nix-daemon || true
    else
        sudo systemctl restart nix-daemon 2>/dev/null || true
    fi
    {{ self_just }} trust-flake-config
    echo "Nix installation complete!"

[private]
_emit_nix_env:
    #!/usr/bin/env cat
    if [ -f "{{ nix_profile }}" ]; then . "{{ nix_profile }}"; fi
    if [ -d "{{ nix_bin_dir }}" ]; then export PATH="{{ nix_bin_dir }}:$HOME/.nix-profile/bin:$PATH"; fi

[private]
_emit_flake_ref:
    #!/usr/bin/env cat
    FLAKE_REF='.'
    if [ -f "{{ submodule_path }}/.gitkeep" ] || [ -f "{{ submodule_path }}/.git" ]; then
        FLAKE_REF='.?submodules=1'
    elif git config -f .gitmodules --get-regexp '^submodule\.secrets/files\.path$' >/dev/null 2>&1; then
        echo "secrets/files submodule is unavailable; continuing with files-example fallback."
    fi
    export FLAKE_REF

[private]
_write_username:
    #!/usr/bin/env bash
    printf '"%s"\n' "$(whoami)" > username.nix

# Switch NixOS configuration
[group('config')]
nixos hostname='':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$(uname)" = "Darwin" ]; then
        echo "Refusing to run NixOS switch on macOS. Use 'just darwin' instead." >&2
        exit 1
    fi
    if [ ! -e /etc/NIXOS ]; then
        echo "Refusing to run NixOS switch on non-NixOS Linux. Use 'just system' instead." >&2
        exit 1
    fi
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    {{ self_just }} _write_username
    flake="$FLAKE_REF"
    if [ -n "{{ hostname }}" ]; then
        flake="$FLAKE_REF#{{ hostname }}"
    fi
    sudo nixos-rebuild switch --accept-flake-config --flake "$flake" --option eval-cache false

# Switch home-manager configuration
[group('config')]
home:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$(uname)" = "Darwin" ]; then
        echo "Refusing to run standalone Home Manager on macOS. Use 'just darwin' instead." >&2
        exit 1
    fi
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    {{ self_just }} _write_username
    # Use Home Manager directly on Linux. `nh home switch` can fail when an
    # older generation references a GC'd derivation during diff/metadata
    # handling, even though the current flake evaluates and activates fine.
    backup_extension="{{ home_manager_backup_extension }}"
    # --option eval-cache false: nix fingerprints local git flakes by commit hash
    # only, ignoring ?submodules=1. Without this, initialising the submodule
    # after a no-secrets switch hits a stale cache entry and keeps deploying
    # the files-example fallback.
    if command -v home-manager >/dev/null 2>&1; then
        home-manager switch -b "$backup_extension" --flake "$FLAKE_REF" --option eval-cache false
    else
        nix run nixpkgs#home-manager -- switch -b "$backup_extension" --flake "$FLAKE_REF" --option eval-cache false
    fi

# Switch system-manager configuration
[group('config')]
system:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$(uname)" = "Darwin" ]; then
        echo "Refusing to run system-manager on macOS. Use 'just darwin' instead." >&2
        exit 1
    fi
    if [ -e /etc/NIXOS ]; then
        echo "Refusing to run system-manager on NixOS. Use 'just deploy <target>' or nixos-rebuild instead." >&2
        exit 1
    fi
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    {{ self_just }} _write_username
    for unit in restic-backup.service restic-backup.timer; do
        path="/etc/systemd/system/$unit"
        legacy="$HOME/.config/restic-systemd/$unit"
        if [ -L "$path" ] && [ "$(readlink "$path")" = "$legacy" ]; then
            sudo rm "$path"
        fi
    done
    wants_path="/etc/systemd/system/timers.target.wants/restic-backup.timer"
    if [ -L "$wants_path" ]; then
        wants_target="$(readlink "$wants_path")"
        case "$wants_target" in
            "$HOME/.config/restic-systemd/restic-backup.timer"|*hm_.configresticsystemdresticbackup.timer)
                sudo rm "$wants_path"
                ;;
        esac
    fi
    nix run --accept-flake-config "$FLAKE_REF#system-manager" -- switch --sudo --flake "$FLAKE_REF" --nix-option eval-cache false

# Switch nix-darwin configuration
[group('config')]
darwin hostname='':
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    {{ self_just }} _write_username
    hostname_args=()
    if [ -n "{{ hostname }}" ]; then
        hostname_args+=(--hostname "{{ hostname }}")
    fi
    if command -v nh >/dev/null 2>&1; then
        nh darwin switch --accept-flake-config "${hostname_args[@]}" "$FLAKE_REF" -- --option eval-cache false
    else
        nix run --accept-flake-config nixpkgs#nh -- darwin switch --accept-flake-config "${hostname_args[@]}" "$FLAKE_REF" -- --option eval-cache false
    fi

# Format all nix files
[group('dev')]
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    nix fmt .

# Push this repository and any submodule commits it references
[group('dev')]
push:
    #!/usr/bin/env bash
    set -euo pipefail
    git push --recurse-submodules=on-demand

# Check flake
[group('dev')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    if [ "$(uname)" = "Darwin" ]; then
        arch="$(uname -m)"
        case "$arch" in
            arm64) system="aarch64-darwin" ;;
            x86_64) system="x86_64-darwin" ;;
            *) echo "Unsupported macOS arch: $arch" >&2; exit 1 ;;
        esac
        nix flake check --accept-flake-config --system "$system" --no-build
    else
        nix flake check --accept-flake-config --all-systems --no-build
    fi

# Build the NanoPi R4S SD image
[group('config')]
build-nanopi-image:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    nix build --accept-flake-config "$FLAKE_REF#packages.aarch64-linux.somo-nanopi-r4s-image"

# Deploy NixOS configuration to remote host
[group('config')]
deploy target:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    nix develop --accept-flake-config "$FLAKE_REF" -c deploy "$FLAKE_REF#{{ target }}" --skip-checks

# Deploy NixOS via target-side nixos-rebuild.
[group('config')]
deploy-rebuild target:
    #!/usr/bin/env bash
    set -euo pipefail
    local_hostname="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    target="{{ target }}"
    if [ "$local_hostname" = "$target" ]; then
        echo "Already on $target; running local NixOS switch..."
        {{ self_just }} nixos "$target"
        exit 0
    fi
    host="$(nix eval --accept-flake-config "$FLAKE_REF#deploy.nodes.$target.hostname" --raw)"
    remote_dir="/home/yifan/nix"
    ssh "root@$host" "install -d -o yifan -g users -m 755 '$remote_dir'"
    rsync -az --delete --delete-excluded --chown=yifan:users \
        --exclude='result' \
        ./ "root@$host:$remote_dir/"
    ssh "root@$host" \
        "set -euo pipefail
        nixos-rebuild switch --accept-flake-config --flake 'path:$remote_dir#$target' \
            --option substituters '{{ deploy_rebuild_substituters }}'"
