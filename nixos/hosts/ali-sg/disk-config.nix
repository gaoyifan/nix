{...}: {
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/disk/by-id/virtio-t4nhxr04pwt8mv9ja45w";
    imageSize = "8G";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
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
            extraArgs = ["-L" "nixos-root"];
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
