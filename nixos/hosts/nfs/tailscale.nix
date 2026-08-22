{...}: {
  imports = [../../optional/tailscale-gnet.nix];

  services.tailscale.extraUpFlags = ["--advertise-routes=202.38.93.0/24"];
}
