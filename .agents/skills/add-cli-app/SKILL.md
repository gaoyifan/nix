---
name: add-cli-app
description: Add a command to this repository's dynamic CLI apps, lazy Home Manager wrappers, and binary-cache build. Use when exposing either an official Nixpkgs program or a package defined under pkgs/ as a flake CLI app.
---

# Add a CLI app

1. Add the command to `appSpecs` in `cli-apps.nix`. This generates the flake app and lazy Home Manager wrapper. Set `program`, `wrapperName`, `wrapperArgs`, or `enableWrapper = false` only when the defaults are wrong.

2. Select the package source:

   - For an official Nixpkgs package, map the app name directly in `mkPackages`:

     ```nix
     command = pkgs.package;
     ```

   - For a custom package, use its exported `customPackages` attribute. Custom packages are already merged into `mkPackages`; add an explicit mapping only when the app name differs:

     ```nix
     command = customPackages.package;
     ```

   Ensure the selected derivation has `meta.mainProgram`, or set `program` in `appSpecs`.

3. Add `.#packages.${{ matrix.system }}.<app>` to the `Build CLI apps` array in `.github/workflows/build.yml`.

4. Validate:

   ```sh
   nix build --accept-flake-config .#<app>
   nix run --accept-flake-config .#<app> -- --version
   ```
