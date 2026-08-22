{lib, ...}: {
  fileSystems = {
    "/" = {
      device = "pool0/nixos/root";
      fsType = "zfs";
    };
    "/boot" = {
      device = "/dev/disk/by-id/usb-HP_iLO_Internal_SD-CARD_000002660A01-0:0-part1";
      fsType = "xfs";
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
