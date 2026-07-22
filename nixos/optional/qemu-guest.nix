# Common support for NixOS guests running under QEMU/KVM.
{modulesPath, ...}: {
  imports = [(modulesPath + "/profiles/qemu-guest.nix")];

  services.qemuGuest.enable = true;
}
