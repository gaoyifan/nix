{...}: {
  imports = [../../optional/tailscale-gnet-vm-exit.nix];

  services.tailscale.extraUpFlags = ["--advertise-routes=202.38.93.0/24"];
}
