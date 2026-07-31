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

   The executable defaults to the app name. Set `program`, `wrapperName`, `wrapperArgs`, or `enableWrapper = false` only when their defaults are wrong. Keep simple and aliased specs on one line, but allow Alejandra to expand multi-setting specs; do not merge attribute sets solely to force a one-line definition.

4. Update the `Build CLI apps` array in `.github/workflows/build.yml` only for packages that this repository must publish to its R2 binary cache:

   - For a package defined under `pkgs/`, add `.#packages.${{ matrix.system }}.<app>`.
   - Do not add apps mapped directly to official Nixpkgs packages. They already use the upstream Nixpkgs binary cache, so building and publishing them again would duplicate that cache.

5. Validate:

   ```sh
   nix build --accept-flake-config .#<app>
   nix run --accept-flake-config .#<app> -- --version
   ```
