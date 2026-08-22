{...}: {
  imports = [../../optional/tailscale-gnet.nix];

  services.tailscale = {
    port = 6627;
    extraUpFlags = ["--advertise-routes=202.38.93.0/24"];
  };
}
