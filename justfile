# Nix profile path
nix_profile := "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"

# Default recipe: ensures nix is installed, then applies the appropriate configuration
default: ensure-nix
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{ nix_profile }}" ]; then . "{{ nix_profile }}"; fi
    if [ "$(uname)" = "Darwin" ]; then
        echo "Detected macOS, applying nix-darwin configuration..."
        just darwin
    else
        echo "Detected Linux, applying home-manager configuration..."
        just home
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
        sudo launchctl kickstart -k system/org.nixos.nix-daemon 2>/dev/null || true
    else
        sudo systemctl restart nix-daemon 2>/dev/null || true
    fi
    mkdir -p ~/.local/share/nix
    printf '%s\n' '{"substituters":{"https://nix-cache.yfgao.net https://cache.nixos.org":true},"trusted-public-keys":{"nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=":true}}' > ~/.local/share/nix/trusted-settings.json
    echo "Nix installation complete!"

# Switch home-manager configuration
[group('config')]
home:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{ nix_profile }}" ]; then . "{{ nix_profile }}"; fi
    if command -v nh >/dev/null 2>&1; then
        nh home switch --accept-flake-config .
    else
        nix run nixpkgs#nh -- home switch --accept-flake-config .
    fi

# Switch nix-darwin configuration
[group('config')]
darwin:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{ nix_profile }}" ]; then . "{{ nix_profile }}"; fi
    if command -v nh >/dev/null 2>&1; then
        nh darwin switch --accept-flake-config . --
    else
        nix run nixpkgs#nh -- darwin switch --accept-flake-config . --
    fi

# Format all nix files
[group('dev')]
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{ nix_profile }}" ]; then . "{{ nix_profile }}"; fi
    nix fmt .

# Check flake
[group('dev')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{ nix_profile }}" ]; then . "{{ nix_profile }}"; fi
    nix flake check --accept-flake-config --all-systems
