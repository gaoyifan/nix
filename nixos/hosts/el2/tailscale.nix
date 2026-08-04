{config, ...}: let
  flags = [
    "--advertise-connector"
    "--advertise-routes=10.250.10.0/24,11.13.112.0/24,100.64.2.0/24,100.64.110.0/24,192.168.93.0/24,202.38.93.0/24,202.141.162.0/24,202.141.178.0/24,192.168.93.151/32,192.168.225.50/32"
    "--operator=yifan"
  ];
in {
  imports = [../../optional/tailscale-gnet.nix];

  services.tailscale = {
    authKeyFile = "${config.services.secrets.filesDir}/nixos/tailscale-auth-key";
    extraSetFlags = flags;
    extraUpFlags = flags;
    port = 6627;
  };
}
