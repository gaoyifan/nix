# somo-minisforum - Minisforum mini PC, always-on Incus (KVM) host.
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./virtualisation.nix
    ./ksm.nix
    ./vms.nix
    ./dnsmasq.nix
    ./newapi.nix
    ./localai-whisper.nix
    ./wifi-ap.nix
    ./tailscale.nix
    ./nylon.nix
    ./nylon-exit.nix
    ./wlt.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = ["mt7921e"];

  fileSystems."/".options = ["compress=zstd" "noatime"];

  hardware.enableRedistributableFirmware = true;

  environment.systemPackages = with pkgs; [
    # Utilities from the NixOS installer base profile, useful for installing or
    # repairing the system.
    ccrypt
    cryptsetup
    ddrescue
    efibootmgr
    efivar
    fuse
    fuse3
    gptfdisk
    hdparm
    iperf3
    jq
    mtr
    ms-sys
    nvme-cli
    parted
    pciutils
    pv
    screen
    sdparm
    smartmontools
    socat
    sshfs-fuse
    tcpdump
    unzip
    usbutils
    vim
    zip

    dnsutils # dig, for debugging the dnsmasq resolver
    tsshd # launched by tssh --udp over the initial SSH connection
  ];

  # This host cannot reach cache.nixos.org reliably: prefer Chinese mirrors
  # instead (SJTU covers paths USTC's sync lags on), keep the personal cache
  # for custom overlay packages, and leave cache.nixos.org as the last fallback.
  nix.settings = {
    substituters = lib.mkForce [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://nix-cache.yfgao.net?priority=50"
      "https://cache.nixos.org?priority=100"
    ];
    trusted-public-keys = [
      "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
    ];
  };

  system.stateVersion = "26.05";
}
