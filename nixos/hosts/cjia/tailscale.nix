{...}: let
  routeFlags = ["--advertise-routes=100.65.1.0/24"];
in {
  services.tailscale = {
    extraUpFlags = routeFlags;
  };
}
