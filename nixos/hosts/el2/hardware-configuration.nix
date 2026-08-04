{lib, ...}: {
  boot.initrd.availableKernelModules = [
    "aacraid"
    "uhci_hcd"
    "ehci_pci"
    "xhci_pci"
    "ahci"
    "nvme"
    "sd_mod"
    "sr_mod"
  ];
  boot.kernelModules = [
    "i40e"
    "igb"
    "kvm-intel"
  ];

  swapDevices = [];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
