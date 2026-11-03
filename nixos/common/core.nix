# Core system defaults shared by all NixOS hosts.
{
  config,
  lib,
  pkgs,
  ...
}: {
  time.timeZone = lib.mkDefault "Asia/Singapore";

  # Containers use their host's kernel; other hosts build in livepatch support.
  boot.kernelPatches = lib.mkIf config.boot.kernel.enable [
    {
      name = "livepatch";
      patch = null;
      structuredExtraConfig.LIVEPATCH = lib.kernel.yes;
    }
  ];

  programs = {
    nix-ld.enable = true;
    zsh.enable = true;
  };
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
