# Core system defaults shared by all NixOS hosts.
{
  lib,
  pkgs,
  ...
}: {
  time.timeZone = lib.mkDefault "Asia/Singapore";
  i18n.defaultLocale = "en_US.UTF-8";

  programs.zsh.enable = true;
  services.tailscale.port = 6627;

  environment.systemPackages = with pkgs; [
    btop
    ccrypt
    curl
    dnsutils
    ethtool
    fuse
    fuse3
    git
    iperf3
    jq
    mtr
    pv
    screen
    socat
    sshfs-fuse
    tmux
    tcpdump
    tsshd
    unzip
    vim
    wget
    zip
  ];
}
