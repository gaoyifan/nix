{lib, ...}: {
  boot.initrd.availableKernelModules = [
    "vmw_pvscsi"
    "vmxnet3"
    "xhci_pci"
    "ahci"
    "sd_mod"
    "sr_mod"
  ];
  boot.kernelModules = ["kvm-intel"];

  swapDevices = [];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
