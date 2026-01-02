# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix` / `flake.lock`: flake entrypoint and pinned inputs.
- `home-manager/home.nix`: primary Home Manager config (shared across platforms).
- `darwin/configuration.nix`: nix-darwin system config (macOS).
- `modules/`: reusable Home Manager modules (e.g., `modules/shell/`, `modules/neovim.nix`).
- `pkgs/`: custom packages exported via `pkgs/default.nix` and `overlays/default.nix`.
- `.github/workflows/build.yml`: CI builds the main configurations on Linux/macOS.

## Build, Test, and Development Commands
- `direnv allow`: load the flake devshell automatically via `.envrc` (optional).
- `nix develop`: enter the dev shell (includes `nh`, `just`, `nil`, `alejandra`).
- `just`: ensure Nix is installed and apply the appropriate configuration for the current OS.
- `just home`: apply Home Manager via `nh home switch` (Linux/standalone use).
- `just darwin`: apply nix-darwin via `nh darwin switch` (macOS use).
- `just fmt`: format Nix files (`nix fmt .`).
- `just check`: run `nix flake check --all-systems` (the main validation step).

## Coding Style & Naming Conventions
- Format with `nix fmt` (uses `alejandra`); prefer formatter-driven changes over manual reflow.
- Keep modules small and composable; put cross-cutting config in `modules/` and import from `home-manager/home.nix`.
- Custom packages: add `pkgs/<name>.nix`, export it from `pkgs/default.nix` as `<name>`, then consume as `pkgs.<name>`.

## Testing Guidelines
- This repo primarily validates via evaluation/build checks: run `just check` before opening a PR.
- To validate a specific output locally:
  - `nix build .#lazyssh`
  - `nix build .#homeConfigurations.yifan.config.home.activationPackage`
  - `nix build .#darwinConfigurations.default.system`

## Security & Configuration Tips
- CI signs and uploads closures using repository secrets; never commit keys or tokens.
- When updating inputs, prefer targeted lock updates (e.g., `nix flake lock --update-input nixpkgs`) and keep `flake.lock` changes intentional.

## Commit & Pull Request Guidelines
- Use the existing conventional-style subjects: `feat(scope): ...`, `fix: ...`, `refactor: ...`, `ci: ...`, `chore: ...`, `style: ...`.
- Keep PRs focused and include what you tested (OS + command, e.g., `just check` / `just darwin`).
- Don’t commit `result` / `result-*` build outputs (they are gitignored).
