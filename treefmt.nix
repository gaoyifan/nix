{
  lib,
  pkgs,
  ...
}: {
  projectRootFile = "flake.nix";

  settings.global.excludes = [".vscode/settings.json"];

  programs = {
    alejandra.enable = true;
    actionlint.enable = true;
    just.enable = true;
    prettier.enable = true;
    ruff-check.enable = true;
    ruff-format = {
      enable = true;
      lineLength = 120;
    };
    rubocop.enable = true;
    shellcheck.enable = true;
    shfmt.enable = true;
  };

  settings.formatter = {
    actionlint.includes = lib.mkForce [".github/workflows/*.yml" ".github/workflows/*.yaml"];
    just.includes = lib.mkForce ["justfile" "Justfile"];
    prettier.includes = lib.mkForce ["*.json" "*.yaml" "*.yml"];
    ruff-check.includes = lib.mkForce ["*.py"];
    ruff-format.includes = lib.mkForce ["*.py"];
    rubocop = {
      includes = lib.mkForce ["*.rb"];
      options = ["--autocorrect-all" "--disable-pending-cops" "--only" "Layout"];
    };
    shellcheck.includes = lib.mkForce ["*.sh" "*.bash"];
    shfmt.includes = lib.mkForce ["*.sh" "*.bash"];
    zsh = {
      command = "${pkgs.bash}/bin/bash";
      options = [
        "-euc"
        ''for file in "$@"; do ${pkgs.zsh}/bin/zsh -n "$file"; done''
        "--"
      ];
      includes = ["*.zsh"];
    };
  };
}
