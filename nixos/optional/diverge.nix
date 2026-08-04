{
  inputs,
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.services.diverge;
  configFile = pkgs.writeText "diverge.conf" ''
    [global]
    listen = 127.0.0.1:1054

    [CN]
    addresses = 223.5.5.5 223.6.6.6
    protocol = udp
    port = 53
    ips = chnroutes.txt

    [X]
    addresses = 1.1.1.1 1.0.0.1
    protocol = https
    tls_dns_name = cloudflare-dns.com
  '';
in {
  options.services.diverge.enable = lib.mkEnableOption "diverge DNS upstream selector";

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers = {
      backend = "podman";
      containers.diverge = {
        image = "ghcr.io/gaoyifan/diverge-rs:master";
        volumes = [
          "${inputs.chnroutes2}/chnroutes.txt:/chnroutes.txt:ro"
          "${configFile}:/diverge.conf:ro"
        ];
        extraOptions = ["--network=host"];
      };
    };
  };
}
