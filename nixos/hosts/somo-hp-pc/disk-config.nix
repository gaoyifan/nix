{
  disko.devices.disk.system = {
    device = "/dev/disk/by-id/nvme-eui.e8238fa6bf530001001b448b47b7daba";
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
            mountOptions = ["compress=zstd" "noatime"];
          };
        };
      };
    };
  };
}
