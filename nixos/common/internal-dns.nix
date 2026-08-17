# Internal LAN zones: resolved delegates on every host, dnsmasq on homeRouter.
{
  config,
  lib,
  options,
  ...
}: let
  zones = {
    "cjia.gaof.net" = "100.65.1.254";
    "el.gaof.net" = "100.64.1.254";
    "el2.gaof.net" = "100.64.2.254";
    "somo.gaof.net" = "100.65.2.254";
    "somo2.gaof.net" = "100.65.12.254";
    "taildeb190.ts.net" = "100.100.100.100";
  };
  homeRouterEnabled = options.networking ? homeRouter && config.networking.homeRouter.enable;
in {
  services.resolved.dnsDelegates =
    lib.mapAttrs (domain: nameserver: {
      Delegate = {
        DNS = [nameserver];
        Domains = [domain];
      };
    })
    zones;

  services.dnsmasq.settings.server = lib.mkIf homeRouterEnabled (
    lib.mkBefore (
      lib.mapAttrsToList (domain: nameserver: "/${domain}/${nameserver}") (
        lib.filterAttrs (domain: _: domain != config.networking.homeRouter.dnsmasq.domain) zones
      )
    )
  );
}
