# Core system defaults shared by all hosts.
{
  lib,
  pkgs,
  ...
}: {
  time.timeZone = lib.mkDefault "Asia/Singapore";
  i18n.defaultLocale = "en_US.UTF-8";

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    btop
    curl
    git
    tmux
    vim
    wget
  ];
}
