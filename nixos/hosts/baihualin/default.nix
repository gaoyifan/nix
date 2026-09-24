{
  imports = [
    ../../optional/nanopi-r5c.nix
    ./networking.nix
  ];

  networking.hostName = "baihualin";
  services.tailscale.extraUpFlags = [
    "--advertise-routes=100.66.1.0/24,fd9a:2d16:5c3e:6601::/64"
  ];

  system.stateVersion = "26.05";
}
