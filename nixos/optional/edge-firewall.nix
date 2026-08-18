{
  config,
  lib,
  options,
  ...
}: let
  cfg = config.networking.edgeFirewall;
  types = lib.types;
  homeRouterEnabled = lib.hasAttrByPath ["networking" "homeRouter" "enable"] options && config.networking.homeRouter.enable;
  nylonEnabled = lib.hasAttrByPath ["services" "nylon" "enable"] options && config.services.nylon.enable;
  trustedInterfaces =
    lib.optionals config.services.tailscale.enable ["tailscale0"]
    ++ lib.optionals nylonEnabled ["nylon0"]
    ++ lib.optionals homeRouterEnabled config.networking.homeRouter.internalInterfaces
    ++ cfg.extraTrustedInterfaces;
  publicTcpPorts =
    lib.optionals config.services.openssh.enable (map toString config.services.openssh.ports)
    ++ ["5201"]
    ++ cfg.extraPublicTcpPorts;
  publicUdpPorts =
    ["5201"]
    ++ lib.optionals nylonEnabled [(toString config.services.nylon.udpPort)]
    ++ lib.optionals config.services.tailscale.enable [(toString config.services.tailscale.port)]
    ++ ["61001-61999"]
    ++ cfg.extraPublicUdpPorts;
  nftSet = values: lib.concatMapStringsSep ", " toString values;
  interfaceSet = lib.concatMapStringsSep ", " (interface: ''"${interface}"'') (lib.unique trustedInterfaces);
  extraInputRules = lib.concatStringsSep "\n" cfg.extraInputRules;
  extraForwardRules = lib.concatStringsSep "\n" cfg.extraForwardRules;
in {
  options.networking.edgeFirewall = {
    enable = lib.mkEnableOption "default-deny edge firewall";

    extraTrustedInterfaces = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional interfaces allowed to access local services and initiate forwarded traffic.";
    };

    extraPublicTcpPorts = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional TCP ports and ranges accepted from untrusted interfaces.";
    };

    extraPublicUdpPorts = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional UDP ports and ranges accepted from untrusted interfaces.";
    };

    extraInputRules = lib.mkOption {
      type = types.listOf types.lines;
      default = [];
      description = "Host-specific nftables input rules evaluated before the common policy.";
    };

    extraForwardRules = lib.mkOption {
      type = types.listOf types.lines;
      default = [];
      description = "Host-specific nftables forwarding rules evaluated before trusted interfaces.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.nftables.enable = true;
    networking.nftables.tables.edge-filter = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter; policy drop;
          ${extraInputRules}

          ct state established,related accept
          iifname "lo" accept
          ip protocol icmp accept
          meta l4proto ipv6-icmp accept

          ${lib.optionalString (trustedInterfaces != []) "iifname { ${interfaceSet} } accept"}
          tcp dport { ${nftSet (lib.unique publicTcpPorts)} } accept
          udp dport { ${nftSet (lib.unique publicUdpPorts)} } accept
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
          ${extraForwardRules}
          ct state established,related accept
          ${lib.optionalString (trustedInterfaces != []) "iifname { ${interfaceSet} } accept"}
        }
      '';
    };
  };
}
