{...}: {
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/disk/by-id/scsi-3600fa4d0d8f744bc9aac8773c2876d70";
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
