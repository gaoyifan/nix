{
  pkgs,
  lib,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;

  # Vim configuration (shared across platforms)
  vimConfig = pkgs.fetchFromGitHub {
    owner = "amix";
    repo = "vimrc";
    rev = "46294d589d15d2e7308cf76c58f2df49bbec31e8";
    sha256 = "sha256-g1appWgZlE27Rm8gorGp9B1c6UvGhg1bESgHk8umJ8g=";
  };

  # Neovim init configuration (shared across platforms)
  neovimExtraConfig = ''
    set runtimepath+=~/.vim_runtime

    source ~/.vim_runtime/vimrcs/basic.vim
    source ~/.vim_runtime/vimrcs/filetypes.vim
    source ~/.vim_runtime/vimrcs/plugins_config.vim
    source ~/.vim_runtime/vimrcs/extended.vim
    try
      source ~/.vim_runtime/my_configs.vim
    catch
    endtry
  '';
in {
  # Link the ultimate vimrc (shared across platforms)
  home.file.".vim_runtime".source = vimConfig;

  # On non-Darwin: use programs.neovim (closure is small, ~40MB with gcc-lib)
  programs.neovim = lib.mkIf (!isDarwin) {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    extraConfig = neovimExtraConfig;
  };

  # On Darwin: manually implement config (neovim installed via Homebrew, see hosts/darwin.nix)
  # This avoids the 800MB+ nix neovim closure on macOS
  xdg.configFile."nvim/init.vim" = lib.mkIf isDarwin {
    text = neovimExtraConfig;
  };

  # Set default editor (matches programs.neovim.defaultEditor behavior)
  # On non-Darwin, programs.neovim handles this; on Darwin, we set it manually
  home.sessionVariables = lib.mkIf isDarwin {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
