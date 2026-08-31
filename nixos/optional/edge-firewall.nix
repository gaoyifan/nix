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
  networkdDhcpModes = map (network: network.networkConfig.DHCP or "no") (lib.attrValues config.systemd.network.networks);
  dhcpV4Client = config.networking.useDHCP || lib.any (mode: lib.elem mode ["yes" "ipv4"]) networkdDhcpModes;
  dhcpV6Client = config.networking.useDHCP || lib.any (mode: lib.elem mode ["yes" "ipv6"]) networkdDhcpModes;
  dhcpServerInterfaces = lib.unique (
    lib.optionals homeRouterEnabled (
      map
      (lan: lan.interface)
      (lib.filter (lan: lan.dhcpServer.range != null) (lib.attrValues config.networking.homeRouter.lans))
    )
  );
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
  interfaceSet = interfaces: lib.concatMapStringsSep ", " (interface: ''"${interface}"'') interfaces;
  dhcpServerRules = lib.optionalString (dhcpServerInterfaces != []) ''
    iifname { ${interfaceSet dhcpServerInterfaces} } udp dport 67 accept
  '';
  dhcpClientRules = lib.concatStringsSep "\n" (
    lib.optional dhcpV4Client "udp sport 67 udp dport 68 accept"
    ++ lib.optional dhcpV6Client "udp sport 547 udp dport 546 accept"
  );
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
    networking.firewall.enable = false;
    networking.nftables.enable = true;
    networking.nftables.tables.edge-filter = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter; policy drop;
          ct state established,related accept
          ${dhcpServerRules}
          ${lib.optionalString config.virtualisation.docker.enable ''
          iifname "docker0" meta l4proto { tcp, udp } th dport 53 accept
        ''}
          ${extraInputRules}
          ${dhcpClientRules}

          iifname "lo" accept
          ip protocol icmp accept
          meta l4proto ipv6-icmp accept

          ${lib.optionalString (trustedInterfaces != []) "iifname { ${interfaceSet (lib.unique trustedInterfaces)} } accept"}
          tcp dport { ${nftSet (lib.unique publicTcpPorts)} } accept
          udp dport { ${nftSet (lib.unique publicUdpPorts)} } accept
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
          ct state established,related accept
          ${extraForwardRules}
          ${lib.optionalString config.virtualisation.docker.enable ''
          iifname "docker0" accept
          iifname "br-*" accept
        ''}
          ${lib.optionalString (trustedInterfaces != []) "iifname { ${interfaceSet (lib.unique trustedInterfaces)} } accept"}
        }
      '';
    };
  };
}
