# somo-nanopi-r4s - NanoPi R4S staged replacement for the SOMO gateway.
{
  imports = [
    ../../optional/nanopi-r4s.nix
    ./networking.nix
    ./tailscale.nix
  ];

  system.stateVersion = "26.05";
}
