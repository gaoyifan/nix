# Oh my Nix

This repository is public primarily as a reference for people putting together their own Nix setup.

It is a personal flake covering:

- macOS machines via `nix-darwin`
- Linux user environments via `home-manager`
- NixOS hosts, including the `exp0` router
- A small set of custom packages under [`pkgs/`](pkgs)

## Layout

- [`flake.nix`](flake.nix): flake entrypoint and outputs
- [`justfile`](justfile): day-to-day commands
- [`darwin/`](darwin): macOS system configuration
- [`home-manager/`](home-manager): shared user environment
- [`nixos/`](nixos): NixOS hosts and modules
- [`pkgs/`](pkgs): custom packages exposed by the flake overlay
- [`secrets/`](secrets): secret modules and CI-safe placeholders

## Quick Start

This is not intended to be a turnkey setup. It is my actual personal configuration, with private pieces removed or replaced by placeholders.

You can still clone it and inspect or build the public parts:

```bash
git clone git@github.com:gaoyifan/nix.git
cd nix
```

If you want to evaluate or adapt it locally:

```bash
just check
```

`just` is the main entry point if you want to use the repo directly:

- macOS: runs `just darwin`
- Linux: runs `just home`

If Nix is not installed yet, `just` will bootstrap it via the Determinate Systems installer.

## Common Commands

```bash
# Apply the current machine configuration
just

# Apply only the Home Manager profile on Linux
just home

# Apply the nix-darwin system on macOS
just darwin

# Format all Nix files
just fmt

# Validate the flake
just check

# Deploy a NixOS target through deploy-rs
just deploy exp0
```

## Flake Outputs

The flake exposes:

- `packages.<system>.*`: custom packages from [`pkgs/default.nix`](pkgs/default.nix)
- `devShells.<system>.default`: development shell used by CI and local development
- `legacyPackages.<system>.homeConfigurations.<username>`: standalone Home Manager configs for Linux
- `darwinConfigurations.<hostname>`: integrated macOS system configs
- `nixosConfigurations.exp0`: NixOS router configuration

Examples:

```bash
# Enter the dev shell
nix develop

# Build a custom package
nix build .#lazyssh

# Build the default darwin system
nix build .#darwinConfigurations.default.system
```

## Secrets

The main repository is public. Real secrets live in a private submodule:

- `secrets/files/`: private submodule with real secrets
- `secrets/files-example/`: tracked placeholders used in CI and public builds

When the private submodule is absent, the public repo automatically falls back to `files-example`, so CI and external readers can still evaluate and build the flake safely.

See [`docs/secrets.md`](docs/secrets.md) for setup, migration, and adding new secrets.

## Notes For Readers

- Treat this repo as a collection of patterns rather than a reusable module set.
- Hostnames, package choices, and layout reflect one real environment, not a generic template.
- The most reusable parts are likely the `justfile`, the flake structure, the `home-manager/` modules, and the `nixos/modules/router/` modules.

## Development Notes

- Run `just fmt` before committing.
- Run `just check` before opening a PR.
- Do not commit `result/` symlinks or build outputs.
