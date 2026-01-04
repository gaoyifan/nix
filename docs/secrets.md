# Secrets Management

This project uses a **git submodule-based approach** for managing secrets. This provides a simple, low-complexity solution that prevents secrets from leaking to the binary cache while maintaining full Nix compatibility.

## Architecture

```
nix/
├── secrets/              # Private git submodule (real secrets)
│   ├── default.nix       # Nix module interface
│   └── atuin/key         # Atuin encryption key
│
├── secrets-example/      # Public placeholder (tracked in main repo)
│   ├── default.nix       # Identical Nix module interface
│   └── atuin/key         # Dummy placeholder key
│
└── home-manager/home.nix # Imports secrets module based on hostname
```

## How It Works

| Component | Purpose | Git Tracking |
|-----------|---------|--------------|
| `secrets/` | Private submodule with real secrets | Separate private repo |
| `secrets-example/` | Placeholder for CI/binary cache | Main repo |

### Submodule Detection

The configuration automatically detects if the private `secrets/` submodule is available:

```nix
# In home-manager/home.nix
secretsModule =
  if builtins.pathExists ../secrets/default.nix
  then ../secrets          # Production (submodule checked out)
  else ../secrets-example; # CI / Public builds
```

- **CI/Public builds** do not have access to the private repo/submodule → loads `secrets-example/`
- **Production builds** have the submodule checked out → loads `secrets/` submodule

### Binary Cache Safety

Since CI only has access to `secrets-example/`, the binary cache will only ever contain derivations built with placeholder secrets. Real secrets never touch the cache.

## Usage

### Initial Setup (new machine)

```bash
# Clone with submodules
git clone --recurse-submodules git@github.com:gaoyifan/nix.git

# Or initialize after cloning
git submodule update --init
```

### Apply Configuration

```bash
# macOS (uses ?submodules=1 automatically)
just darwin

# Or manually
sudo darwin-rebuild switch --flake '.?submodules=1'
```

### CI / GitHub Actions

No special setup needed. CI uses `secrets-example/` automatically because:
1. Submodule is not checked out (no access to private repo)

## Adding New Secrets

### Step 1: Add to Both Directories

Create identical file structure in both `secrets/` and `secrets-example/`:

```bash
# Real secret
echo "actual-secret-value" > secrets/myapp/token

# Placeholder
echo "PLACEHOLDER_FOR_CI" > secrets-example/myapp/token
```

### Step 2: Update Module Interface

Add matching options to both `default.nix` files:

```nix
# In options.services.secrets
myapp = {
  enable = mkEnableOption "MyApp secret deployment";
  tokenFile = mkOption {
    type = types.path;
    default = "${secretsDir}/myapp/token";
  };
};

# In config
(mkIf cfg.myapp.enable {
  home.file.".config/myapp/token".source = cfg.myapp.tokenFile;
})
```

### Step 3: Enable in home.nix

```nix
services.secrets.myapp.enable = true;
```

### Step 4: Commit Changes

```bash
# Commit submodule
cd secrets
git add -A && git commit -m "Add myapp token" && git push

# Update main repo
cd ..
git add secrets secrets-example
git commit -m "feat: add myapp secret"
git push
```

## Currently Managed Secrets

| Secret | Target Path | Option |
|--------|-------------|--------|
| Atuin sync key | `~/.local/share/atuin/key` | `services.secrets.atuin.enable` |

## Security Considerations

> **Note:** This approach stores secrets in **cleartext** in a private git repository. While simpler than sops/age/KMS solutions, ensure your private repository has appropriate access controls.

### What This Protects Against
- ✅ Secrets leaking to public binary cache
- ✅ Secrets appearing in public git history
- ✅ CI builds requiring secret access

### What This Does NOT Protect Against
- ❌ Secrets at rest on target machine (stored as regular files)
- ❌ Compromise of the private secrets repository
- ❌ Users with read access to `~/.local/share/` or similar paths

For higher security requirements, consider [sops-nix](https://github.com/Mic92/sops-nix) or [agenix](https://github.com/ryantm/agenix).
