{...}: {
  imports = [../../optional/vm-qemu-bios-virtio];

  networking.hostName = "xtom-sjc";

  systemd.network.networks."10-wan" = {
    address = ["142.147.94.11/24"];
    routes = [
      {
        Gateway = "142.147.94.1";
        GatewayOnLink = true;
      }
    ];
  };
}
