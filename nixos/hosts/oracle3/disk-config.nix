{...}: {
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/disk/by-id/scsi-3606fbdbbf245496faea7c89fce316b27";
    imageSize = "8G";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };
        swap = {
          size = "2G";
          content.type = "swap";
        };
        root = {
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
