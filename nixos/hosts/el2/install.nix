{lib, ...}: {
  # Keep the exported PVE pool untouched until NixOS and networking pass
  # their first-boot checks and the pool is explicitly rebuilt.
  boot.zfs.extraPools = lib.mkForce [];
  virtualisation.incusVms.enable = lib.mkForce false;
}
