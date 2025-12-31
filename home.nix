{
  config,
  pkgs,
  lib,
  customPkgs,
  ...
}:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  imports = [
    ./modules/shell
    ./modules/neovim.nix
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = lib.mkDefault "yifan";
  home.homeDirectory = lib.mkDefault (if isDarwin then "/Users/yifan" else "/home/yifan");

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # Git
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
    (lib.lowPrio pkgs.nh)
    # Custom packages
    customPkgs.lazyssh
  ];

  # NH Configuration
  home.sessionVariables = {
    NH_FLAKE = "${config.home.homeDirectory}/nix";
  };

  # Git Configuration
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Yifan Gao";
        email = "git@yfgao.com";
      };
      push.autoSetupRemote = true;
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta.navigate = true;
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Auto clean nix store (only on non-darwin, as nix-darwin manages gc at system level)
  nix.gc.automatic = !isDarwin;
}
