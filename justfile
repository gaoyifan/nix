# Nix profile path
nix_profile := "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
nix_bin_dir := "/nix/var/nix/profiles/default/bin"
submodule_path := "secrets/files"
home_manager_backup_extension := "backup-$(date +%Y%m%d-%H%M%S)"
self_just := quote(just_executable()) + " --justfile " + quote(justfile()) + " --working-directory " + quote(justfile_directory()) + " --quiet"

# Default recipe: pulls the latest code, then applies the appropriate configuration
default:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Pulling latest repository changes..."
    git pull
    {{ self_just }} ensure-nix
    source <({{ self_just }} _emit_nix_env)
    if [ "$(uname)" = "Darwin" ]; then
        echo "Detected macOS, applying nix-darwin configuration..."
        {{ self_just }} darwin
    else
        echo "Detected Linux, applying home-manager configuration..."
        {{ self_just }} home
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
    mkdir -p ~/.local/share/nix
    printf '%s\n' '{"substituters":{"https://nix-cache.yfgao.net https://cache.nixos.org":true},"trusted-public-keys":{"nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=":true}}' > ~/.local/share/nix/trusted-settings.json
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
        nix flake check --accept-flake-config --all-systems
    fi

# Deploy NixOS configuration to remote host
[group('config')]
deploy target:
    #!/usr/bin/env bash
    set -euo pipefail
    source <({{ self_just }} _emit_nix_env)
    source <({{ self_just }} _emit_flake_ref)
    nix develop --accept-flake-config -c deploy .#{{ target }} --skip-checks

# Apply home-manager, then install restic systemd timer
[group('config')]
restic-setup:
    restic-install-systemd-timer
    systemctl status restic-backup.timer
