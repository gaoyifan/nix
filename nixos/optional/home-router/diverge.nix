{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.homeRouter;
  configFile = pkgs.writeText "diverge.conf" ''
    [global]
    listen = 127.0.0.1:1054

    [CN]
    addresses = 223.5.5.5 223.6.6.6
    protocol = udp
    port = 53
    ips = ${inputs.chnroutes2}/chnroutes.txt

    [X]
    addresses = 1.1.1.1 1.0.0.1
    protocol = https
    tls_dns_name = cloudflare-dns.com
  '';
in {
  imports = [inputs.diverge.nixosModules.default];

  config = lib.mkIf cfg.enable {
    services.diverge = {
      enable = true;
      configFile = configFile;
    };
    services.dnsmasq.settings.server = ["127.0.0.1#1054"];
  };
}
