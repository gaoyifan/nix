{
  imports = [
    ../../optional/nanopi-r5c.nix
    ./networking.nix
    ./pppoe.nix
    ./services.nix
    ./tailscale.nix
  ];

  networking.hostName = "cjia";

  # R5C Ethernet controllers have no readable factory MAC and otherwise get
  # a different random address on every boot.
  systemd.network.links = {
    "10-wan0".linkConfig.MACAddress = "26:03:3b:3b:6f:bf";
    "10-lan1".linkConfig.MACAddress = "32:ef:18:8d:6d:e7";
  };

  system.stateVersion = "26.05";
}
