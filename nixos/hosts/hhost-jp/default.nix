{...}: {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/vm-qemu-bios-virtio
  ];

  networking = {
    hostName = "hhost-jp";
    edgeFirewall.enable = true;
  };

  systemd.network.networks."10-wan" = {
    address = [
      "103.27.187.241/24"
      "2403:ad80:89:4c00:15:0:8c0:6b7c/56"
    ];
    routes = [
      {
        Gateway = "103.27.187.1";
        GatewayOnLink = true;
      }
      {
        Gateway = "2403:ad80:89:4c00::1";
        GatewayOnLink = true;
      }
    ];
  };
}
