# Secrets Management

This project stores encrypted secrets in a private git submodule and decrypts them at activation time with [agenix](https://github.com/ryantm/agenix). Plaintext secret contents are not embedded in Nix derivations or copied into `/nix/store`.

## Architecture

```
nix/
├── secrets/
│   ├── default.nix       # Shared source selection for NixOS modules
│   ├── home.nix          # Unified Nix module logic
│   ├── files/            # Private git submodule (encrypted secrets)
│   │   ├── .gitkeep      # Marker file for detection
│   │   ├── secrets.nix    # Private recipient registry and access matrix
│   │   └── home/
│   │       └── atuin-key.age
│   └── files-example/    # Non-secret metadata for public evaluation
```

## How It Works

| Component | Purpose | Git Tracking |
|-----------|---------|--------------|
| `secrets/default.nix` | Shared encrypted-source selection for NixOS modules | Main repo |
| `secrets/home.nix` | Home Manager agenix declarations | Main repo |
| `secrets/files/` | Encrypted files | Separate private repo |
| `secrets/files/secrets.nix` | Named public keys and per-file authorization matrix | Private submodule |
| `secrets/files-example/` | Non-secret metadata for CI/public evaluation | Main repo |

### Auto-Detection Logic

The `secrets/default.nix` module checks for the presence of `secrets/files/.gitkeep`.
- **Found**: Sets `config.services.secrets.filesDir = ./files` (Production/Personal machine).
- **Not Found**: Sets `config.services.secrets.filesDir = ./files-example` (CI/Public builds).

### Runtime Decryption

NixOS imports agenix's system module. Each NixOS consumer declares its own `age.secrets` entry beside the service configuration. Home Manager imports its user module; on Linux it uses a systemd user unit and on Darwin a launchd agent. Decrypted paths are runtime paths such as `/run/agenix/...` or `$HOME/.local/share/atuin/...`. nix-darwin does not import the agenix system module because there are currently no Darwin system-level secret consumers.

`system-manager` does not import agenix. Its Restic unit reads the runtime file created by Home Manager (`$HOME/.config/restic/env`); `just` applies Home Manager before system-manager on non-NixOS Linux.

Home Manager declares user-level agenix secrets only for Darwin configurations whose user identity has been verified and added to the private recipient registry. Other Darwin configurations remain usable without those declarations until their keys are recorded and the ciphertexts are rekeyed.

### Shared Host Keys

- `nixos/wlt-ssh-host-key`: shared SSH host private key for the WLT selector service. Keep it host-agnostic so multiple gateways serving the same WLT domain present the same SSH host identity.
- `nixos/internal-ca.pem`, `nixos/internal-ca-key.pem`: internal CA certificate and private key for locally issued service certificates.
- `nixos/wlt-server.pem`, `nixos/wlt-server-key.pem`: HTTPS server certificate and private key for WLT, signed by the internal CA. The server certificate should cover the public WLT aliases plus their split-horizon `wlt-ipv4.*` and `wlt-ipv6.*` API hosts.

### Recipient registry

`secrets/files/secrets.nix` is the single source of truth for named identities and the authorization matrix. It is intentionally kept in the private submodule; this document does not copy host names, public keys, or access relationships. Change the private rules file, then run `agenix --rekey` from `secrets/files/`.

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

### Step 1: Add an encrypted file

Add a recipient rule in `secrets/files/secrets.nix`, then create the encrypted file from any directory with `just edit-secret`. The path is relative to the directory where `just` is invoked:

```bash
just edit-secret secrets/files/home/myapp-token.age
```

No dummy secret file is needed in `secrets/files-example/`; keep only the non-secret metadata required to evaluate the host modules.

### Step 2: Declare it beside its consumer

NixOS modules should declare and consume system secrets together. User-level secrets follow the same pattern in `secrets/home.nix`; add a public option only when another module genuinely needs to override the path:

```nix
age.secrets.myapp-token = lib.mkIf config.services.myapp.enable {
  file = config.services.secrets.filesDir + "/home/myapp-token.age";
  path = "/run/agenix/myapp-token";
};

services.myapp.tokenFile = "/run/agenix/myapp-token";
```

For a Home Manager secret, keep the encrypted source and its activation path in `secrets/home.nix`:

```nix
age.secrets.myapp-token = lib.mkIf cfg.myapp.enable {
  file = ./files/home/myapp-token.age;
  path = "${config.home.homeDirectory}/.config/myapp/token";
};
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
