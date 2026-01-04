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

  # Select secrets module based on whether submodule is initialized
  # CI builds don't have submodule access, so they use secrets-example
  secretsSubmoduleExists = builtins.pathExists ../secrets/default.nix;
  secretsModule =
    if secretsSubmoduleExists
    then ../secrets
    else ../secrets-example;
in {
  imports = [
    ./shell.nix
    ./neovim.nix
    secretsModule
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

    # lowPrio to avoid conflict with nix-darwin's nh
    (lib.lowPrio nh)

    # Custom package from ./pkgs (via overlay)
    lazyssh
    dcv

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

  # Enable atuin sync key deployment from secrets module
  services.secrets.atuin.enable = true;

  # Auto gc on Linux only - darwin handles this at system level
  nix.gc.automatic = !isDarwin;
}
