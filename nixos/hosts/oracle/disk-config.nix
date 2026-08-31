{...}: {
  disko.devices.disk.system = {
    device = "/dev/disk/by-id/scsi-3609d35e87ce64a9e991d5da58311a82d";
    imageSize = "8G";
    content.partitions = {
      ESP.priority = 1;
      swap = {
        priority = 2;
        size = "2G";
        content.type = "swap";
      };
      root.priority = 3;
    };
  };
}
