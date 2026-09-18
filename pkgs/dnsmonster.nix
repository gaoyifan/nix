{pkgs}:
pkgs.dnsmonster.overrideAttrs (old: {
  # Capture all Linux interfaces as IP packets, including loopback and TUN.
  patches = (old.patches or []) ++ [./dnsmonster/any-interface.patch];
})
