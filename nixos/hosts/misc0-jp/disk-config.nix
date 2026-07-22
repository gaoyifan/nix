{...}: {
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          priority = 1;
          size = "1M";
          type = "EF02";
        };
        swap = {
          priority = 2;
          size = "2G";
          content.type = "swap";
        };
        root = {
          priority = 3;
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
