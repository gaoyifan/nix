# Home Manager configuration
# Shared between standalone home-manager and darwin-integrated home-manager
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  rimeIce = pkgs.fetchFromGitHub {
    owner = "iDvel";
    repo = "rime-ice";
    rev = "51003473600d90ff4b46004a5122ee1b98210606";
    hash = "sha256-4BJrs+PkC4flA7a6ZrATNT+CtUdUuoWKb62Mw5t91q4=";
  };
in {
  imports = [
    ./shell.nix
    ./neovim.nix
    ../secrets/home.nix
  ];

  home.username = lib.mkDefault "yifan";
  home.homeDirectory = lib.mkDefault (
    if isDarwin
    then "/Users/yifan"
    else "/home/yifan"
  );
  home.stateVersion = "25.11"; # Do not change - see home-manager release notes

  home.packages = with pkgs; [
    # Git tools
    delta
    difftastic
    diffutils

    # Core utilities
    tmux
    curl
    wget
    tree
    uv
    ripgrep
    unstablePkgs.just
    fzf

    # lowPrio to avoid conflict with nix-darwin's nh
    (lib.lowPrio nh)

    # Custom package from ./pkgs (via overlay)
    lazyssh
    dcv

    # External flake package
    inputs.witr.packages.${stdenv.hostPlatform.system}.default
  ];

  # Cargo binaries (rust tools installed via cargo install)
  home.sessionPath =
    [
      "${config.home.homeDirectory}/.cargo/bin"
      "${config.home.homeDirectory}/.local/bin"
    ]
    ++ lib.optionals (!isDarwin) [
      "/home/linuxbrew/.linuxbrew/opt/rustup/bin"
    ];

  # nh (nix helper) configuration
  home.sessionVariables.NH_FLAKE = "${config.home.homeDirectory}/nix";

  programs.git = {
    enable = true;
    package = pkgs.gitMinimal;
    settings = {
      user = {
        name = "Yifan Gao";
        email = "git@yfgao.com";
      };
      push.autoSetupRemote = true;
      # Delta for better diffs
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta.navigate = true;
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
  };

  programs.home-manager.enable = true;

  home.activation.rimeIce = lib.mkIf isDarwin (lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -euo pipefail
    target="${config.home.homeDirectory}/Library/Rime"
    src="${rimeIce}"

    if [ -e "$target" ] && [ ! -d "$target" ]; then
      echo "home-manager: $target exists and is not a directory; skipping rime-ice sync."
      exit 0
    fi

    mkdir -p "$target"
    ${pkgs.rsync}/bin/rsync -a --delete \
      --exclude "build/" \
      --exclude "installation.yaml" \
      --exclude "rime_ice.userdb/" \
      --exclude "user.yaml" \
      --chmod=Du+w,Fu+w \
      "$src/" "$target/"
  '');

  # Enable atuin sync key deployment from secrets module
  services.secrets.atuin.enable = true;

  # Auto gc on Linux only - darwin handles this at system level
  nix.gc.automatic = !isDarwin;
}
