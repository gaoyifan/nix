{...}: {
  disko.devices.disk.system = {
    device = "/dev/disk/by-id/scsi-3606fbdbbf245496faea7c89fce316b27";
    imageSize = "8G";
    content.partitions.swap = {
      size = "2G";
      content.type = "swap";
    };
  };
}
