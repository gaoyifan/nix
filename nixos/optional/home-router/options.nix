{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter;
  types = lib.types;
  interfaceForVlan = vlan: "${cfg.switch.name}.${toString vlan}";
  internalLanNames = lib.filter (name: !cfg.lans.${name}.guest) (lib.attrNames cfg.lans);
  internalInterfaceNames = lib.unique (map (name: cfg.lans.${name}.interface) internalLanNames);
in {
  options.networking.homeRouter = {
    enable = lib.mkEnableOption "home router network stack";

    switch = {
      name = lib.mkOption {
        type = types.str;
        readOnly = true;
        default = "br-core";
        description = "Name of the VLAN-aware core bridge managed by this module.";
      };

      ports = lib.mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            bond = lib.mkOption {
              type = types.nullOr (types.submodule {
                options = {
                  members = lib.mkOption {
                    type = types.listOf types.str;
                    description = "Physical members of the active-backup bond.";
                  };
                  primary = lib.mkOption {
                    type = types.str;
                    description = "Preferred member of the active-backup bond.";
                  };
                };
              });
              default = null;
              description = "Active-backup bond configuration; null denotes an ordinary port.";
            };
            untagged = lib.mkOption {
              type = types.nullOr (types.ints.between 1 4094);
              default = null;
              example = 1;
              description = "VLAN carried untagged on this port.";
            };
            tagged = lib.mkOption {
              type = types.listOf (types.ints.between 1 4094);
              default = [];
              example = [652 654];
              description = "VLANs carried tagged on this port.";
            };
          };
        });
        default = {};
        description = "Physical ports and active-backup bonds attached to the core switch.";
      };
    };

    lans = lib.mkOption {
      type = types.attrsOf (types.submodule ({
        config,
        name,
        ...
      }: let
        lan = config;
      in {
        options = {
          vlan = lib.mkOption {
            type = types.ints.between 1 4094;
            default = 1;
            description = "VLAN carrying this LAN on the core switch.";
          };
          interface = lib.mkOption {
            type = types.str;
            readOnly = true;
            default = interfaceForVlan lan.vlan;
            description = "Host VLAN interface derived from the LAN VLAN.";
          };
          altnames = lib.mkOption {
            type = types.listOf types.str;
            default = [name];
            description = "Alternative names assigned to the host VLAN interface.";
          };
          addresses = lib.mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Gateway addresses held by the host on this LAN.";
          };
          dns = lib.mkOption {
            type = types.listOf types.str;
            default = [];
            description = "DNS servers associated with this LAN.";
          };
          domains = lib.mkOption {
            type = types.listOf types.str;
            default = [];
            description = "DNS search and route-only domains associated with this LAN.";
          };
          guest = lib.mkOption {
            type = types.bool;
            default = false;
            description = "Whether this is a guest LAN excluded from internal services.";
          };
          ipv6 = {
            enable = lib.mkOption {
              type = types.bool;
              default = true;
              description = "Whether to announce IPv6 configuration on this LAN.";
            };
            prefixes = lib.mkOption {
              type = types.listOf types.str;
              default = [];
              description = "IPv6 prefixes announced on this LAN.";
            };
          };
        };
      }));
      default = {};
      description = "Internal networks for which the host acts as gateway.";
    };

    wans = lib.mkOption {
      type = types.attrsOf (types.submodule ({
        config,
        name,
        ...
      }: let
        wan = config;
      in {
        options = {
          vlan = lib.mkOption {
            type = types.nullOr (types.ints.between 1 4094);
            default = null;
            description = "Core-switch VLAN carrying this WAN.";
          };
          device = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Standalone physical device carrying this WAN.";
          };
          interface = lib.mkOption {
            type = types.str;
            readOnly = true;
            default =
              if wan.vlan != null
              then interfaceForVlan wan.vlan
              else if wan.device != null
              then wan.device
              else "";
            description = "Host interface derived from the WAN attachment.";
          };
          altnames = lib.mkOption {
            type = types.listOf types.str;
            default = [name];
            description = "Alternative names assigned to the WAN interface.";
          };
          addresses = lib.mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Host addresses for this upstream routing identity.";
          };
          dhcp = lib.mkOption {
            type = types.bool;
            default = false;
            description = "Whether this WAN obtains addresses through DHCP and accepts IPv6 router advertisements.";
          };
          gateway4 = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "IPv4 upstream gateway.";
          };
          gateway6 = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "IPv6 upstream gateway.";
          };
          routingTable = lib.mkOption {
            type = types.nullOr (types.ints.between 1 4294967295);
            default = null;
            description = "Dedicated route table and conntrack mark for this WAN.";
          };
          defaultRoute = lib.mkOption {
            type = types.bool;
            default = false;
            description = "Whether static gateways also install default routes in the main table.";
          };
          masquerade = {
            ipv4SourceSubnets = lib.mkOption {
              type = types.listOf types.str;
              default = [];
              description = "IPv4 source subnets masqueraded through this WAN.";
            };
            ipv6SourceSubnets = lib.mkOption {
              type = types.listOf types.str;
              default = [];
              description = "IPv6 source subnets masqueraded through this WAN.";
            };
          };
        };
      }));
      default = {};
      description = "Upstream routing identities attached by VLAN or physical device.";
    };

    routingPolicies = lib.mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          from = lib.mkOption {
            type = types.str;
            description = "LAN whose IPv4 source prefixes select this policy.";
          };
          via = lib.mkOption {
            type = types.str;
            description = "DHCP WAN supplying this policy's default route.";
          };
        };
      });
      default = {};
      description = "IPv4 source-routing policies that pin LANs to DHCP WANs.";
    };

    internalInterfaces = lib.mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = internalInterfaceNames;
      description = "Host interfaces belonging to non-guest LANs.";
    };

  };
}
