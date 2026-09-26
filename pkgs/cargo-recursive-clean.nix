{pkgs}:
pkgs.rustPlatform.buildRustPackage (finalAttrs: {
  pname = "cargo-recursive-clean";
  version = "0.2.4";

  src = pkgs.fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-thwpyLtPHDwg9L04gW4cQP9GWdwnyyfHQrKWx7q5eDU=";
  };

  cargoHash = "sha256-EsSGhpWR/QmQFo1D157hArq1vVNsd4CUHl4bEwc+ZjY=";

  meta = {
    description = "Clean Rust projects recursively";
    homepage = "https://github.com/OLoKo64/cargo-recursive-clean";
    license = pkgs.lib.licenses.mit;
    mainProgram = "cargo-recursive-clean";
  };
})
