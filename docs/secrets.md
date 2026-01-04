# Secrets Management

This project uses a **git submodule-based approach** for managing secrets, with an intelligent auto-detection mechanism. This prevents secrets from leaking to the binary cache while maintaining full Nix compatibility.

## Architecture

```
nix/
├── secrets/
│   ├── default.nix       # Entry point (Auto-detects real vs example)
│   ├── home.nix          # Unified Nix module logic
│   ├── files/            # Private git submodule (Real secrets)
│   │   ├── .gitkeep      # Marker file for detection
│   │   └── home/
│   │       └── atuin-key # Real key
│   └── files-example/    # Public placeholders (Tracked in main repo)
│       └── home/
│           └── atuin-key # Dummy key
```

## How It Works

| Component | Purpose | Git Tracking |
|-----------|---------|--------------|
| `secrets/default.nix` | Auto-detects if `secrets/files` is available | Main repo |
| `secrets/files/` | Private submodule with real secrets | Separate private repo |
| `secrets/files-example/` | Placeholder for CI/binary cache | Main repo |

### Auto-Detection Logic

The `secrets/default.nix` module checks for the presence of `secrets/files/.gitkeep`.
- **Found**: Sets `config.services.secrets.filesDir = ./files` (Production/Personal machine).
- **Not Found**: Sets `config.services.secrets.filesDir = ./files-example` (CI/Public builds).

### Binary Cache Safety

Since CI only has access to `files-example/`, the binary cache will only ever contain derivations built with placeholder secrets. Real secrets never touch the cache.

## Usage

### Initial Setup (new machine)

```bash
# Clone with submodules
git clone --recurse-submodules git@github.com:gaoyifan/nix.git

# Or initialize after cloning
git submodule update --init --recursive
```

### Migration / Troubleshooting

#### Error: "refusing to create/use ... in another submodule's git dir"

If you are pulling these changes an existing machine that used the old `secrets` submodule structure, you might see this error because the old submodule's git metadata conflicts with the new nested structure.

**Fix:**
Run this command from the repo root to remove the stale git module data and re-initialize:

```bash
rm -rf .git/modules/secrets && git submodule update --init --force
```

### Apply Configuration

```bash
# macOS
just darwin

# Linux
just home
```

## Adding New Secrets

### Step 1: Add to Both Directories

Create identical file structure in both `secrets/files/` and `secrets/files-example/`:

```bash
# Real secret
echo "actual-secret-value" > secrets/files/home/myapp-token

# Placeholder
echo "PLACEHOLDER_FOR_CI" > secrets/files-example/home/myapp-token
```

### Step 2: Update Module Interface

Update `secrets/home.nix`:

```nix
# In options.services.secrets
myapp = {
  enable = mkEnableOption "MyApp secret deployment";
  tokenFile = mkOption {
    type = types.path;
    default = "${cfg.filesDir}/home/myapp-token";
  };
};

# In config
(mkIf cfg.myapp.enable {
  home.file.".config/myapp/token".source = cfg.myapp.tokenFile;
})
```

### Step 3: Commit Changes

```bash
# Commit submodule
cd secrets/files
git add -A && git commit -m "Add myapp token" && git push

# Update main repo
cd ../..
git add secrets/files secrets/files-example secrets/home.nix
git commit -m "feat: add myapp secret"
git push
```

