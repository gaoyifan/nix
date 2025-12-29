{
  config,
  pkgs,
  isDarwin,
  ...
}: {
  imports = [
    ./modules/shell
    ./modules/vim
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "yifan";
  home.homeDirectory =
    if isDarwin
    then "/Users/yifan"
    else "/home/yifan";

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
    # Core utilities
    tmux
    curl
    wget
    delta # git pager

    # Custom tools mentioned in zsh plugins (dependencies)
    # docker # Managed by system? Adding just in case or assume system docker
    # python3 # for some plugins

    # Custom tools
    tree
  ];

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
}
