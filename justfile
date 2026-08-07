# Nix profile path
nix_profile := "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
nix_bin_dir := "/nix/var/nix/profiles/default/bin"
submodule_path := "secrets/files"
home_manager_backup_extension := "backup-$(date +%Y%m%d-%H%M%S)"
nanopi_builder := "ssh-ng://yifan@100.127.101.9?remote-program=/nix/var/nix/profiles/default/bin/nix-daemon&base64-ssh-public-host-key=c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBuVENJd3dGSUJ0ZmZVTmd0TG5Yb0FFc0dtbFYxVnJHd1VMVHhtME5HSVQ%3D aarch64-linux - 8 1"
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

# Trust this flake's Nix settings for future runs.
[group('setup')]
trust-flake-config:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    mkdir -p ~/.local/share/nix
    nix eval --raw --file nix-cache.nix \
        --apply 'settings: builtins.toJSON {
            extra-substituters = builtins.listToAttrs (map (name: { inherit name; value = true; }) settings.extra-substituters);
            extra-trusted-public-keys = builtins.listToAttrs (map (name: { inherit name; value = true; }) settings.extra-trusted-public-keys);
        }' > ~/.local/share/nix/trusted-settings.json
    echo "Trusted flake settings are up to date."

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
    sudo systemctl restart nix-daemon.service

# Switch nix-darwin configuration
[group('config')]
darwin hostname='':
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    {{ self_just }} _write_username
    if [ -f /etc/nix/nix.custom.conf ] && [ ! -L /etc/nix/nix.custom.conf ]; then
        backup="/etc/nix/nix.custom.conf.before-nix-darwin.$(date +%Y%m%d-%H%M%S)"
        echo "Moving the existing Determinate Nix custom configuration to $backup..."
        sudo mv /etc/nix/nix.custom.conf "$backup"
    fi
    hostname_args=()
    if [ -n "{{ hostname }}" ]; then
        hostname_args+=(--hostname "{{ hostname }}")
    fi
    if command -v nh >/dev/null 2>&1; then
        nh darwin switch --accept-flake-config "${hostname_args[@]}" "$FLAKE_REF" -- --option eval-cache false
    else
        nix run --accept-flake-config nixpkgs#nh -- darwin switch --accept-flake-config "${hostname_args[@]}" "$FLAKE_REF" -- --option eval-cache false
    fi
    sudo launchctl kickstart -k system/systems.determinate.nix-daemon

# Format all supported files
[group('dev')]
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    nix fmt --accept-flake-config

# Check formatting without changing files
[group('dev')]
fmt-check:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    system="$(nix eval --impure --raw --expr builtins.currentSystem)"
    nix build --accept-flake-config --no-link ".#checks.$system.formatting"

# Push this repository and any submodule commits it references
[group('dev')]
push:
    #!/usr/bin/env bash
    set -euo pipefail
    git push --recurse-submodules=on-demand

# Check the configuration used by this machine
[group('dev')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    if [ "$(uname)" = "Darwin" ]; then
        nix eval --accept-flake-config --raw ".#darwinConfigurations.$(hostname -s).system.drvPath" >/dev/null
    elif [ -e /etc/NIXOS ]; then
        nix eval --accept-flake-config --raw ".#nixosConfigurations.$(hostname -s).config.system.build.toplevel.drvPath" >/dev/null
    else
        system="$(nix eval --impure --raw --expr builtins.currentSystem)"
        nix eval --accept-flake-config --raw ".#legacyPackages.$system.homeConfigurations.$(whoami).activationPackage.drvPath" >/dev/null
        nix eval --accept-flake-config --raw ".#systemConfigs.$system.default.drvPath" >/dev/null
    fi

# Check every flake output across all supported platforms
[group('dev')]
check-all:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    if [ "$(uname)" = "Darwin" ]; then
        arch="$(uname -m)"
        case "$arch" in
            arm64) check_system="aarch64-darwin" ;;
            *) echo "Unsupported macOS arch: $arch" >&2; exit 1 ;;
        esac
        nix flake check --accept-flake-config --system "$check_system" --no-build
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
    if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
        echo "build-nanopi-image requires a working SSH agent." >&2
        exit 1
    fi
    sudo --preserve-env=SSH_AUTH_SOCK "$(command -v nix)" build \
        --store local \
        --accept-flake-config \
        --builders "{{ nanopi_builder }}" \
        "$FLAKE_REF#packages.aarch64-linux.somo-nanopi-r4s-image"

# Deploy NixOS configuration to remote host
[group('config')]
deploy target:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    if [ "{{ target }}" = "somo-nanopi-r4s" ]; then
        if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
            echo "deploy somo-nanopi-r4s requires a working SSH agent." >&2
            exit 1
        fi
        sudo --preserve-env=SSH_AUTH_SOCK "$(command -v nix)" develop \
            --store local \
            --accept-flake-config \
            "$FLAKE_REF" \
            -c deploy "$FLAKE_REF#{{ target }}" --skip-checks -- \
            --store local \
            --accept-flake-config \
            --builders "{{ nanopi_builder }}"
    else
        nix develop --accept-flake-config "$FLAKE_REF" \
            -c deploy "$FLAKE_REF#{{ target }}" --skip-checks -- \
            --accept-flake-config
    fi

# Sync the flake and rebuild NixOS on the target.
[group('config')]
sync-and-rebuild target:
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
    ssh "$host" install -d -m 700 .cache/nixos-deploy
    rsync -az --delete --delete-excluded \
        --exclude='result' \
        ./ "$host:.cache/nixos-deploy/"
    ssh "$host" bash -s -- "$target" <<'REMOTE'
    set -euo pipefail
    target="$1"
    repo="$HOME/.cache/nixos-deploy"
    default_substituters="$(
        nix eval --raw --file "$repo/nix-cache.nix" \
            --apply 'settings: builtins.concatStringsSep " " settings.extra-substituters'
    )"
    internal_substituters="$(
        INTERNAL_SUBSTITUTER_HOSTNAME="$target" \
            nix eval --impure --raw --file "$repo/secrets/internal-substituters.nix" \
                --apply 'configure: builtins.concatStringsSep " " (configure { hostname = builtins.getEnv "INTERNAL_SUBSTITUTER_HOSTNAME"; })'
    )"
    sudo nixos-rebuild switch --accept-flake-config \
        --flake "path:$repo#$target" \
        --option substituters https://cache.nixos.org \
        --option extra-substituters "$internal_substituters $default_substituters"
    REMOTE
