---
name: add-cli-app
description: Add a command to this repository's dynamic CLI apps, lazy Home Manager wrappers, and binary-cache build. Use when exposing either an official Nixpkgs program or a package defined under pkgs/ as a flake CLI app.
---

# Add a CLI app

1. Add the command to the recursive `appSpecs` attribute set in `cli-apps.nix`. When the app name matches a top-level package attribute, an empty spec is enough; custom packages take precedence over Nixpkgs:

   ```nix
   command = {};
   ```

2. Use `from` when the package attribute path differs from the app name. Define the package path once and reuse that spec for other commands from the same package:

   ```nix
   go = from "go";
   gofmt = go;
   npm = from ["nodejs-slim" "npm"];
   npx = npm;
   ```

3. Use a regular attribute set when an app has multiple settings:

   ```nix
   copilot = {
     packagePath = ["copilot-cli"];
     wrapperArgs = ["--yolo"];
   };
   ```

   The executable defaults to the app name. Set `program`, `wrapperName`, `wrapperArgs`, or `enableWrapper = false` only when their defaults are wrong. Set `preferWrapper = true` when the lazy wrapper must take precedence over an existing same-name command; this places it in `~/.local/bin` instead of the low-priority lazy-app directory. Keep simple and aliased specs on one line, but allow Alejandra to expand multi-setting specs; do not merge attribute sets solely to force a one-line definition.

4. Do not configure CI separately. `cli-apps.nix` automatically includes apps backed by `customPackages` in the `cli-apps-cache` aggregate and excludes apps backed by official Nixpkgs packages. For a custom package restricted to particular systems, expose it conditionally in `pkgs/default.nix` and set accurate `meta.platforms`; apps and the aggregate follow the attributes available on each system.

5. Validate:

   ```sh
   nix build --accept-flake-config .#<app>
   nix run --accept-flake-config .#<app> -- --version
   ```
