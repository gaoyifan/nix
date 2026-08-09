{
  config,
  lib,
  ...
}: let
  cfg = config.networking.edgeFirewall;
  types = lib.types;
  nftSet = values: lib.concatMapStringsSep ", " toString values;
  interfaceSet = lib.concatMapStringsSep ", " (interface: ''"${interface}"'') cfg.trustedInterfaces;
  extraInputRules = lib.concatStringsSep "\n" cfg.extraInputRules;
  extraForwardRules = lib.concatStringsSep "\n" cfg.extraForwardRules;
in {
  options.networking.edgeFirewall = {
    enable = lib.mkEnableOption "default-deny edge firewall";

    trustedInterfaces = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Interfaces allowed to access local services and initiate forwarded traffic.";
    };

    publicTcpPorts = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "TCP ports and ranges accepted from untrusted interfaces.";
    };

    publicUdpPorts = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "UDP ports and ranges accepted from untrusted interfaces.";
    };

    extraInputRules = lib.mkOption {
      type = types.listOf types.lines;
      default = [];
      description = "Host-specific nftables input rules appended after public service rules.";
    };

    extraForwardRules = lib.mkOption {
      type = types.listOf types.lines;
      default = [];
      description = "Host-specific nftables forwarding rules appended after trusted interfaces.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.nftables.enable = true;
    networking.nftables.tables.edge-filter = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter; policy drop;
          ct state established,related accept
          iifname "lo" accept
          ip protocol icmp accept
          meta l4proto ipv6-icmp accept

          ${lib.optionalString (cfg.trustedInterfaces != []) "iifname { ${interfaceSet} } accept"}
          ${lib.optionalString (cfg.publicTcpPorts != []) "tcp dport { ${nftSet cfg.publicTcpPorts} } accept"}
          ${lib.optionalString (cfg.publicUdpPorts != []) "udp dport { ${nftSet cfg.publicUdpPorts} } accept"}
          ${extraInputRules}
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
          ct state established,related accept
          ${lib.optionalString (cfg.trustedInterfaces != []) "iifname { ${interfaceSet} } accept"}
          ${extraForwardRules}
        }
      '';
    };
  };
}
