{pkgs}:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "jip";
  version = "0.1.3";

  src = pkgs.fetchFromGitHub {
    owner = "PoHsuanLai";
    repo = "jip";
    rev = "501e6a1804609004047a9c437ba3dd3851f27726";
    hash = "sha256-TRGHPLbpQKfesrN7pj0Le276un7BjeY8goZ3Yq3RPWQ=";
  };

  cargoHash = "sha256-tQhdZcoARYF/mciBONnI/i7phtyJthR74/ZyUalgUbo=";

  buildAndTestSubdir = "jip-cli";

  env = {
    CARGO_PROFILE_RELEASE_LTO = "true";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
  };

  stripAllList = ["bin"];

  meta = {
    description = "Modern CLI for Linux networking";
    homepage = "https://github.com/PoHsuanLai/jip";
    license = with pkgs.lib.licenses; [mit asl20];
    mainProgram = "jip";
    platforms = pkgs.lib.platforms.linux;
  };
}
