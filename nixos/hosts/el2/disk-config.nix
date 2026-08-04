{...}: {
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/disk/by-id/ata-Micron_5100_MTFDDAK240TCB_18171C24A25A";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          name = "ESP";
          start = "1M";
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
            extraArgs = ["-L" "nixos-root"];
            mountpoint = "/";
            mountOptions = [
              "compress=zstd"
              "noatime"
            ];
          };
        };
      };
    };
  };
}
