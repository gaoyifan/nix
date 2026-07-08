# Utilities for physical machines: disks, firmware, and hardware diagnostics.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    cryptsetup
    ddrescue
    efibootmgr
    efivar
    gptfdisk
    hdparm
    ms-sys
    nvme-cli
    parted
    pciutils
    sdparm
    smartmontools
    usbutils
  ];
}
