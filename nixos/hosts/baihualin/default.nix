{
  imports = [
    ../../optional/nanopi-r5c.nix
    ./networking.nix
  ];

  networking.hostName = "baihualin";
  # Preserve this board's Ethernet addresses across boots.
  systemd.network.links = {
    "10-wan0".linkConfig.MACAddress = "9e:e5:97:34:9d:5b";
    "10-lan1".linkConfig.MACAddress = "e2:cd:0f:7b:4b:26";
  };
  services.tailscale.extraUpFlags = ["--advertise-routes=100.66.1.0/24"];

  system.stateVersion = "26.05";
}
