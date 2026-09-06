{pkgs}:
pkgs.wrangler.overrideAttrs (_: {
  installPhase = ''
    runHook preInstall

    mv packages/~vitest-pool-workers packages/vitest-pool-workers
    # Export the release files and production dependencies, including workspace
    # packages, instead of retaining the entire monorepo and its devDependencies.
    # Use the shared-lockfile deploy path; legacy deploy re-resolves dependencies
    # and requires registry metadata that is absent from the offline pnpm store.
    pnpm --filter wrangler --prod deploy --config.inject-workspace-packages=true \
      --offline --ignore-scripts "$out/lib"
    # This is only used to type-check Wrangler's own templates. At runtime,
    # esbuild otherwise tries to resolve its omitted workspace devDependency.
    rm "$out/lib/templates/tsconfig.json"

    mkdir -p "$out/bin"
    makeWrapper ${pkgs.lib.getExe pkgs.nodejs} "$out/bin/wrangler" \
      --inherit-argv0 \
      --add-flags "$out/lib/bin/wrangler.js" \
      --set-default SSL_CERT_FILE "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

    runHook postInstall
  '';
})
