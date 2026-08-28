# Internal LAN zones for resolved and the homeRouter WLT-DNS frontend.
{
  config,
  lib,
  ...
}: let
  defaultZones = {
    "cjia.gaof.net" = "100.65.1.254";
    "el.gaof.net" = "100.64.1.254";
    "el2.gaof.net" = "100.64.2.254";
    "somo.gaof.net" = "100.65.2.254";
    "somo2.gaof.net" = "100.65.12.254";
    "taildeb190.ts.net" = "100.100.100.100";
  };
  zones = config.networking.internalDns.zones;
in {
  options.networking.internalDns.zones = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    default = defaultZones;
    description = "Canonical internal DNS suffixes and their literal authoritative backends.";
  };

  config = {
    services.resolved.dnsDelegates =
      lib.mapAttrs (domain: nameserver: {
        Delegate = {
          DNS = [nameserver];
          Domains = [domain];
        };
      })
      zones;
  };
}
