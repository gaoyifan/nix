# Repository Guidelines

## Project Structure

- `flake.nix`: Flake entrypoint with packages, devShells, homeConfigurations, darwinConfigurations, nixosConfigurations
- `darwin/configuration.nix`: nix-darwin system config (macOS) - Homebrew packages/casks, system settings
- `home-manager/`: Home Manager config (shared across platforms) - shell, neovim, packages
- `nixos/`: NixOS configurations and modules (e.g., `exp0/` router, `modules/router/`)
- `pkgs/`: Custom packages exported via `pkgs/default.nix`; overlay defined inline in `flake.nix`
- `secrets/`: Secret modules with `files/` (gitignored submodule) and `files-example/` (CI fallback). See [docs/secrets.md](docs/secrets.md)

## Commands

- `just` / `just darwin` / `just home`: Apply configuration (auto-detects OS)
- `just deploy <target>`: Deploy NixOS via deploy-rs
- `just fmt`: Format with `alejandra`
- `just check`: Validate flake (`--all-systems` on Linux, `--no-build` on Darwin)

## Coding Style

- Format with `nix fmt`; run `just fmt` before committing
- Check `pkgs.stdenv.isDarwin` for platform-specific logic
- Custom packages: add `pkgs/<name>.nix`, export from `pkgs/default.nix`, consume as `pkgs.<name>`
- Keep dynamically loaded apps out of `home.packages`; expose them as flake apps and add a zsh alias that `nix run`s them on demand to shrink Home Manager closures.

## Commits

Use conventional subjects: `feat(scope):`, `fix:`, `refactor:`, `chore:`, `docs:`, `ci:`, `style:`

## Testing

Run `just fmt` and `just check` before opening a PR. Don't commit `result/` outputs.

## CI

GitHub Actions live in `.github/workflows/`:

- `build.yml`: builds Home Manager / nix-darwin closures and dynamically loaded CLI apps on every push/PR; signs and pushes them to the R2 binary cache on `main`.
- `bump-cli-packages.yml`: nightly bump for dynamically loaded CLI packages; auto-commits and triggers `build.yml`.
