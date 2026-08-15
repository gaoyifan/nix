{...}: {
  imports = [
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ../../optional/nylon.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "misc0-jp";
    useDHCP = false;
    useNetworkd = true;
  };

  systemd.network.networks."10-wan" = {
    matchConfig.Type = "ether";
    address = ["103.90.136.69/27"];
    routes = [
      {
        Gateway = "103.90.136.65";
        GatewayOnLink = true;
      }
    ];
    networkConfig = {
      DNS = ["1.1.1.1"];
      IPv6AcceptRA = false;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  boot.loader.grub.enable = true;

  networking.firewall.enable = false;

  services.nylon = {
    enable = true;
    overlay.nat.enable = false;
  };

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}
