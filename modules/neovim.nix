{pkgs, ...}: let
  # Vim configuration
  vimConfig = pkgs.fetchFromGitHub {
    owner = "amix";
    repo = "vimrc";
    rev = "46294d589d15d2e7308cf76c58f2df49bbec31e8";
    sha256 = "sha256-g1appWgZlE27Rm8gorGp9B1c6UvGhg1bESgHk8umJ8g=";
  };
in {
  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # Link the ultimate vimrc
    ".vim_runtime".source = vimConfig;
  };

  # Vim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    extraConfig = ''
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
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
