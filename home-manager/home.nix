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
in {
  imports = [
    ../modules/shell
    ../modules/neovim.nix
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
    just

    # lowPrio to avoid conflict with nix-darwin's nh
    (lib.lowPrio nh)

    # Custom package from ./pkgs (via overlay)
    lazyssh

    # External flake package
    inputs.witr.packages.${stdenv.hostPlatform.system}.default
  ];

  # Cargo binaries (rust tools installed via cargo install)
  home.sessionPath = ["${config.home.homeDirectory}/.cargo/bin"];

  # nh (nix helper) configuration
  home.sessionVariables.NH_FLAKE = "${config.home.homeDirectory}/nix";

  programs.git = {
    enable = true;
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

  # Auto gc on Linux only - darwin handles this at system level
  nix.gc.automatic = !isDarwin;
}
