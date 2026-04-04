# Darwin `gitMinimal` Closure Investigation

Date: 2026-04-05

## Background

After migrating this repository from the `25.11` release branches to unstable:

- `nixpkgs` moved to `nixos-unstable`
- `home-manager` moved to `master`
- `nix-darwin` moved to `master`

the closure of `darwinConfigurations.default.system` increased from:

- `1,299,295,288` bytes on the pre-migration `25.11` system
- to `2,522,260,944` bytes on the unstable system

## Main Cause

The large increase was mostly not caused by user packages. The dominant dependency chain was:

`darwin-system -> system-path -> darwin-option / darwin-rebuild -> git -> python3 -> apple-sdk -> clang/llvm`

The largest additions observed in `diff-closures` were:

- `llvm-21.1.8`
- `apple-sdk-14.4`
- `clang-21.1.8`

## `gitMinimal` Experiments

### 1. Replacing only `darwin-option` / `darwin-rebuild`

I rebuilt `nix-darwin`'s `nix-tools` locally with `git = pkgs.gitMinimal` and replaced:

- `darwin-option`
- `darwin-rebuild`

This did not materially reduce the top-level system closure.

Reason:

- `darwin-uninstaller` embeds another internal `darwin-system`
- that internal system still referenced a default `darwin-rebuild`
- that path pulled full `git` back into the outer closure

### 2. Disabling `darwin-uninstaller`

With:

- `darwin-option` using `gitMinimal`
- `darwin-rebuild` using `gitMinimal`
- `darwin-uninstaller` disabled

the rebuilt `darwin-system` closure dropped to:

- `1,097,192,320` bytes

That was:

- `-1,425,068,624` bytes relative to the unstable system
- `-202,102,968` bytes relative to the original `25.11` system

### 3. Keeping `darwin-uninstaller`, but making it use `gitMinimal`

I also prototyped a custom `darwin-uninstaller` that rebuilds its internal system with:

- `darwin-option` using `gitMinimal`
- `darwin-rebuild` using `gitMinimal`

This version worked locally and no longer depended on:

- full `git`
- `apple-sdk-14.4`

Instead, it depended on `gitMinimal` through its embedded `darwin-rebuild`.

## Decision

This optimization is technically possible, but it adds too much repository-specific complexity for limited value:

- custom replacement of upstream `nix-darwin` tools
- custom replacement of upstream `darwin-uninstaller`
- more indirection in `darwin/configuration.nix`
- more maintenance burden when `nix-darwin` changes upstream

The rough savings were on the order of about `1.3 GiB`, but the code became noticeably less clear.

For this repository, the conclusion is:

- keep the configuration simple
- accept the larger unstable Darwin closure
- avoid carrying local `nix-darwin` tool overrides just to trim this dependency chain
