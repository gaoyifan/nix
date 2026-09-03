{
  imports = [../../../optional/authoritative-ns];

  # Deployment prerequisites are tracked in docs/powerdns-el2-migration.md.
  services.authoritativeNs = {
    role = "primary";
    dataDirectory = "/pool1/services/powerdns";
    wantedBy = ["el2-services.target"];
    requiredUnits = ["zfs-unlock-mount.service"];
    tailscaleSyncers.main = {
      zone = "ts.gaof.net.";
      socketPath = "/run/tailscale/tailscaled.sock";
      sourceUnit = "tailscaled.service";
    };
  };
}
