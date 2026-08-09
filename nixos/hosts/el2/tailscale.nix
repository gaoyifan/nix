{
  config,
  lib,
  ...
}: let
  flags = [
    "--advertise-connector"
    # The control plane intentionally leaves 192.168.93.0/24 unapproved; it is
    # advertised only to work around an exit-node bug. The overlapping
    # 192.168.93.151/32 is the route actually approved for tailnet clients.
    "--advertise-routes=10.250.10.0/24,11.13.112.0/24,100.64.2.0/24,100.64.110.0/24,192.168.93.0/24,202.38.93.0/24,202.141.162.0/24,202.141.178.0/24,192.168.93.151/32,192.168.225.50/32"
  ];
in {
  imports = [../../optional/tailscale-gnet.nix];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    tailscale-auth-key.file = config.services.secrets.filesDir + "/nixos/tailscale-auth-key.age";
  };

  services.tailscale = {
    authKeyFile = "/run/agenix/tailscale-auth-key";
    extraSetFlags = flags;
    extraUpFlags = flags;
    port = 6627;
    serve = {
      enable = true;
      services = {
        immich2.endpoints."tcp:80" = "tcp://127.0.0.1:2283";
        restic-nas.endpoints."tcp:80" = "http://127.0.0.1:8000";
      };
    };
  };
}
