{
  config,
  lib,
  nixosConfigurationName,
  nylonTopology,
  pkgs,
  ...
}: let
  active = nylonTopology;
  managed = builtins.hasAttr nixosConfigurationName active.perHost;
  host = active.perHost.${nixosConfigurationName};
  hasSecrets = config.services.secrets.hasRealFiles;
  hasWarp = managed && host.cloudflareWarp != null;
  isDnsController = managed && nixosConfigurationName == active.dns.controller;
  secretFile = name:
    config.services.secrets.filesDir + "/nixos/${nixosConfigurationName}/${name}.age";
  dnsSnapshot = pkgs.writeText "nylon-powerdns-desired.json" active.dns.text;
  powerdns = lib.getExe pkgs.nylon-powerdns-reconcile;
  powerdnsCredentials = {
    LoadCredential = "api-key:/run/agenix/nylon-powerdns-api-key";
    UMask = "0077";
  };
in {
  imports = [./module.nix];

  config = lib.mkMerge [
    (lib.mkIf managed {
      services.nylon = {
        enable = hasSecrets;
        compiled = host;
        cloudflareWarpPrivateKeyFile =
          if hasWarp
          then "/run/agenix/nylon-wg-cloudflare-private-key"
          else null;
      };

      age.secrets = lib.mkIf hasSecrets (
        {
          nylon-private-key = {
            file = secretFile "nylon-private-key";
          };
        }
        // lib.optionalAttrs hasWarp {
          nylon-wg-cloudflare-private-key = {
            file = secretFile "wg-cloudflare-private-key";
          };
        }
      );
    })

    (lib.mkIf isDnsController {
      environment = {
        etc."nylon/dns-desired.json".source = dnsSnapshot;
        systemPackages = [pkgs.nylon-powerdns-reconcile];
      };

      age.secrets.nylon-powerdns-api-key = lib.mkIf hasSecrets {
        file = secretFile "nylon-powerdns-api-key";
      };

      systemd.services = lib.mkIf hasSecrets {
        nylon-powerdns-plan = {
          description = "Plan reconciliation of Nylon's PowerDNS A/AAAA records";
          wants = ["network-online.target"];
          after = [
            "agenix-install-secrets.service"
            "network-online.target"
          ];
          serviceConfig =
            powerdnsCredentials
            // {
              Type = "oneshot";
              StateDirectory = "nylon-powerdns";
              StateDirectoryMode = "0700";
            };
          script = ''
            set -euo pipefail
            plan=/var/lib/nylon-powerdns/plan.json
            candidate=$(mktemp "$plan.new.XXXXXX")
            trap 'rm -f "$candidate"' EXIT
            ${powerdns} plan \
              --url ${lib.escapeShellArg active.dns.apiUrl} \
              --api-key-file "$CREDENTIALS_DIRECTORY/api-key" \
              --snapshot /etc/nylon/dns-desired.json > "$candidate"
            chmod 0600 "$candidate"
            mv "$candidate" "$plan"
          '';
        };

        nylon-powerdns-apply = {
          description = "Apply a reviewed Nylon PowerDNS reconciliation plan";
          wants = ["network-online.target"];
          after = [
            "agenix-install-secrets.service"
            "network-online.target"
          ];
          unitConfig.ConditionPathExists = "/var/lib/nylon-powerdns/plan.json";
          serviceConfig =
            powerdnsCredentials
            // {
              Type = "oneshot";
            };
          script = ''
            exec ${powerdns} apply \
              --url ${lib.escapeShellArg active.dns.apiUrl} \
              --api-key-file "$CREDENTIALS_DIRECTORY/api-key" \
              --plan /var/lib/nylon-powerdns/plan.json
          '';
        };
      };
    })
  ];
}
