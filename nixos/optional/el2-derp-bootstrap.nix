{...}: {
  # Break the bootstrap loop between the internal DNS delegate and Tailscale.
  networking.hosts = {
    "202.38.93.98" = ["el2.gaof.net"];
    "202.141.162.72" = ["el2.gaof.net"];
    "202.141.178.7" = ["el2.gaof.net"];
  };
}
