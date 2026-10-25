{pkgs}:
pkgs.nix-output-monitor.override (old: {
  extraComposeFunctions =
    (old.extraComposeFunctions or [])
    ++ [
      (pkgs.haskell.lib.compose.appendPatch (pkgs.fetchpatch {
        # Determinate Nix 3.23 emits activity 10113 and result 10111, which nom 2.2.0 rejects.
        # Backport https://github.com/maralorn/nix-output-monitor/pull/321.
        # Remove this override once both locked nixpkgs inputs include that fix.
        name = "nom-unknown-activity-types.patch";
        url = "https://github.com/maralorn/nix-output-monitor/commit/d48ff7935da72a5a5764ee8c5358d38417b0f337.patch";
        relative = "nix-output-monitor";
        hash = "sha256-s/DFz+P9CWMeIEvgdOxQkQnSNDTnV9/fDu4VluYbzG8=";
      }))
    ];
})
