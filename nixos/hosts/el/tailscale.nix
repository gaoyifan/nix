{...}: let
  flags = [
    "--advertise-connector"
    "--advertise-routes=10.254.0.0/21,100.64.0.0/24,100.64.1.0/24,192.168.93.0/24,192.168.174.0/24,202.38.93.0/24,202.141.162.0/24,202.141.178.0/24"
  ];
in {
  services.tailscale = {
    extraUpFlags = flags;
  };
}
