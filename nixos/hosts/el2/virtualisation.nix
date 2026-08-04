{...}: {
  imports = [../../optional/incus-vms];

  virtualisation.incusVms = {
    enable = true;
    pool = {
      driver = "zfs";
      source = "pool1/incus";
    };
    requiredUnits = ["zfs-import-pool1.service"];

    instances.kingdee = {
      vlan = 642;
      macAddress = "CA:52:18:F3:D7:F4";
      rootSize = "512GiB";
      rootConfig = {
        "boot.priority" = "10";
        "io.bus" = "virtio-scsi";
      };
      config = {
        "limits.cpu" = "8";
        "limits.memory" = "32GiB";
        "security.csm" = "true";
        "security.secureboot" = "false";
      };
    };

    instances.debian23-openclaw = {
      vlan = 642;
      macAddress = "BC:24:11:2A:7D:8D";
      rootSize = "32GiB";
      rootConfig."boot.priority" = "10";
      config = {
        "limits.cpu" = "8";
        "limits.memory" = "16GiB";
        "security.csm" = "true";
        "security.secureboot" = "false";
      };
      extraDevices.vm2023-cloudinit = {
        type = "disk";
        source = "/dev/zvol/pool1/vm-2023-cloudinit";
        readonly = "true";
      };
    };
  };
}
