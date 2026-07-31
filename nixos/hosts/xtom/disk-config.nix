{...}: {
  disko.devices.disk.system = {
    type = "disk";
    # xTom exposes one 15 GiB VirtIO disk without a serial/by-id symlink.
    # The PCI slot is identical and stable across all three VMs.
    device = "/dev/disk/by-path/pci-0000:00:04.0";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          priority = 1;
          size = "1M";
          type = "EF02";
        };
        root = {
          priority = 2;
          size = "100%";
          content = {
            type = "filesystem";
            format = "btrfs";
            mountpoint = "/";
            mountOptions = [
              "compress=zstd:3"
              "noatime"
            ];
          };
        };
      };
    };
  };
}
