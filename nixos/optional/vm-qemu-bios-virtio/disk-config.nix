{...}: {
  disko.devices.disk.system = {
    type = "disk";
    # These VMs expose one VirtIO disk without a serial/by-id symlink.
    # Pin the disk to the PCI slot observed on every module consumer.
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
