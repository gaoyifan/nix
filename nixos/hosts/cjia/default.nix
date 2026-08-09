{
  imports = [
    ../../optional/nanopi-r4s.nix
    ./networking.nix
    ./pppoe.nix
    ./services.nix
    ./tailscale.nix
    ./wireguard.nix
  ];

  networking.hostName = "cjia";

  system.stateVersion = "26.05";
}
