{
  inputs,
  pkgs,
}:
(inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
  # The v0.9.2 release's upstream npm-deps hash does not match its lockfile.
  npmDepsHash = "sha256-UXnB6q5tubKpTs+A5+u/NLSzc8ZK6rAsQs+kEphEKd8=";
}).overrideAttrs (old: {
  # Upstream traces node-pty's prebuilds, but npm rebuild puts the addon in build/Release.
  preBuild =
    (old.preBuild or "")
    + ''
      node node_modules/node-gyp/bin/node-gyp.js rebuild \
        --directory packages/server/node_modules/node-pty \
        --nodedir=${old.nodejs}
        test -f packages/server/node_modules/node-pty/build/Release/pty.node
    '';
  postInstall =
    (old.postInstall or "")
    + ''
      install -Dm755 packages/server/node_modules/node-pty/build/Release/pty.node \
            "$out/lib/paseo/packages/server/node_modules/node-pty/build/Release/pty.node"
    '';
  # The v0.9.2 Nix metadata disagrees with the repository's Apache-2.0 LICENSE.
  meta = old.meta // {license = pkgs.lib.licenses.asl20;};
})
