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
    ./vms.nix
    ./adguard.nix
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
    jq
    ms-sys
    nvme-cli
    parted
    pciutils
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

    dnsutils # dig, for debugging the AdGuard Home resolver
    tsshd # launched by tssh --udp over the initial SSH connection
  ];

  # This host cannot reach cache.nixos.org reliably: use Chinese mirrors
  # instead (SJTU covers paths USTC's sync lags on), and keep the personal
  # cache for custom overlay packages.
  nix.settings = {
    substituters = lib.mkForce [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://nix-cache.yfgao.net?priority=50"
    ];
    trusted-public-keys = [
      "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
    ];
  };

  system.stateVersion = "26.05";
}
