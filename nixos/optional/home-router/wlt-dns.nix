{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  homeRouter = config.networking.homeRouter;
  cfg = homeRouter.wlt.dns;
  types = lib.types;
  # Internal deployment ABI: nftables and RPDB rules need the numeric owner at
  # build time, before the target host's passwd database exists.
  dnsUid = 398;

  isIpv6 = address: lib.hasInfix ":" address;
  socketAddress = port: address:
    if isIpv6 address
    then "[${address}]:${toString port}"
    else "${address}:${toString port}";
  internalLans = lib.filterAttrs (_: lan: !lan.guest) homeRouter.lans;
  lanAddresses = lib.concatMap (lan: lan.addresses) (lib.attrValues internalLans);
  lanListenAddresses = map (address: lib.head (lib.splitString "/" address)) lanAddresses;
  listenAddresses = lib.unique (
    lanListenAddresses
    ++ [
      homeRouter.serviceAddresses.ipv4
      homeRouter.serviceAddresses.ipv6
    ]
    ++ lib.optional (lib.elem "wg-iplc" cfg.entryInterfaces) (lib.head (lib.splitString "/" homeRouter.wgIplc.ip))
    ++ cfg.explicitListenAddresses
  );
  listenAddresses4 = lib.filter (address: !isIpv6 address) listenAddresses;
  listenAddresses6 = lib.filter isIpv6 listenAddresses;
  entryInterfaces = lib.unique (homeRouter.internalInterfaces ++ cfg.entryInterfaces);

  allowedClientCidrs = lib.unique (
    lanAddresses
    ++ lib.optionals (lib.elem "tailscale0" entryInterfaces) [
      "100.64.0.0/10"
      "fd7a:115c:a1e0::/48"
    ]
    ++ cfg.extraAllowedClientCidrs
  );
  allowedClientCidrs4 = lib.filter (cidr: !isIpv6 cidr) allowedClientCidrs;
  allowedClientCidrs6 = lib.filter isIpv6 allowedClientCidrs;

  internalZones = config.networking.internalDns.zones;
  ownDomain = homeRouter.dnsmasq.domain;
  remoteZones = lib.filterAttrs (domain: _: domain != ownDomain) internalZones;
  localBackendAddresses = lib.unique (["127.0.0.1"] ++ lib.attrValues remoteZones);
  unmarkedDestinationCidrs = lib.unique (
    allowedClientCidrs
    ++ map (address:
      if isIpv6 address
      then "${address}/128"
      else "${address}/32")
    localBackendAddresses
  );
  unmarkedDestinationCidrs4 = lib.filter (cidr: !isIpv6 cidr) unmarkedDestinationCidrs;
  unmarkedDestinationCidrs6 = lib.filter isIpv6 unmarkedDestinationCidrs;

  aliyunEndpoints4 = [
    "223.5.5.5"
    "223.6.6.6"
  ];
  aliyunEndpoints6 = [
    "2400:3200::1"
    "2400:3200:baba::1"
  ];
  cloudflareEndpoints4 = [
    "1.1.1.1"
    "1.0.0.1"
  ];
  cloudflareEndpoints6 = [
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
  ];
  publicEndpoints4 = aliyunEndpoints4 ++ cloudflareEndpoints4;
  publicEndpoints6 = aliyunEndpoints6 ++ cloudflareEndpoints6;

  localRoutes =
    [
      {
        name = "local-dhcp";
        domains = [ownDomain];
        unqualified = true;
        reverse_cidrs = lanAddresses;
        servers = ["127.0.0.1:1053"];
        timeout_milliseconds = 2000;
      }
    ]
    ++ lib.mapAttrsToList (domain: backend: {
      name = domain;
      domains = [domain];
      servers = [(socketAddress 53 backend)];
      timeout_milliseconds = 2000;
    })
    remoteZones;

  generatedConfigFile = (pkgs.formats.toml {}).generate "wlt-dns.toml" {
    server = {
      listen = map (socketAddress 53) listenAddresses;
      max_response_ttl = 60;
      max_udp_payload = 1232;
      max_dns_message = 65535;
      max_doh_body = 65535;
      max_tcp_connections = 512;
      max_tcp_connections_per_client = 64;
      max_inflight_queries = 2048;
      tcp_idle_timeout_seconds = 30;
      shutdown_timeout_seconds = 10;
    };
    policy = {
      family = "inet";
      table = "home-router";
      ipv4_map = "src2mark";
      ipv6_map = "src2mark6";
      default_eligible_interfaces = homeRouter.internalInterfaces;
      ipv4_default_mark = lib.fromHexString homeRouter.wgIplc.mark;
      ipv6_default_mark = 4095;
    };
    local_routes = localRoutes;
    dns_servers = {
      aliyun = {
        protocol = "udp";
        ipv4_endpoints = map (socketAddress 53) aliyunEndpoints4;
        ipv6_endpoints = map (socketAddress 53) aliyunEndpoints6;
      };
      cloudflare = {
        protocol = "https";
        ipv4_endpoints = map (socketAddress 443) cloudflareEndpoints4;
        ipv6_endpoints = map (socketAddress 443) cloudflareEndpoints6;
        tls_name = "cloudflare-dns.com";
        http_path = "/dns-query";
      };
    };
    outlet_groups = [
      {
        title = "国内出口";
        mask = lib.fromHexString "0xFFF000";
        dns_server = "aliyun";
        default = false;
        domain_files = [];
        ip_files = [
          "${inputs.chnroutes2}/chnroutes.txt"
          "${inputs.china-operator-ip}/china6.txt"
        ];
        outlets."默认" = 0;
        outlets_v6."默认" = 0;
      }
      {
        title = "海外出口";
        mask = lib.fromHexString "0xFFF";
        dns_server = "cloudflare";
        default = true;
        domain_files = [];
        ip_files = [];
        outlets."默认" = 0;
        outlets_v6."默认" = 0;
        overrides = [
          {
            outlet_regex = "^CN ";
            dns_server = "aliyun";
          }
        ];
      }
    ];
    cache = {
      max_entries = 10000;
      max_weight_bytes = 64 * 1024 * 1024;
    };
    metrics.listen = "127.0.0.1:9421";
  };

  nftAddressSet = values: "{ ${lib.concatStringsSep ", " values} }";
  nftInterfaceSet = values: "{ ${lib.concatMapStringsSep ", " (value: ''"${value}"'') values} }";
  frontDoorBypassRules = lib.concatStringsSep "\n" (
    lib.optional (listenAddresses4 != []) ''iifname ${nftInterfaceSet entryInterfaces} ip daddr ${nftAddressSet listenAddresses4} meta l4proto { tcp, udp } th dport 53 meta mark set 0 ct mark set 0 return''
    ++ lib.optional (listenAddresses6 != []) ''iifname ${nftInterfaceSet entryInterfaces} ip6 daddr ${nftAddressSet listenAddresses6} meta l4proto { tcp, udp } th dport 53 meta mark set 0 ct mark set 0 return''
  );
  outputBypassRules = lib.concatStringsSep "\n" (
    lib.optional (unmarkedDestinationCidrs4 != []) ''meta skuid ${toString dnsUid} ip daddr != ${nftAddressSet publicEndpoints4} ip daddr ${nftAddressSet unmarkedDestinationCidrs4} meta mark set 0 ct mark set 0 return''
    ++ lib.optional (unmarkedDestinationCidrs6 != []) ''meta skuid ${toString dnsUid} ip6 daddr != ${nftAddressSet publicEndpoints6} ip6 daddr ${nftAddressSet unmarkedDestinationCidrs6} meta mark set 0 ct mark set 0 return''
  );
  firewallAcceptRules = lib.concatStringsSep "\n" (
    lib.optional (listenAddresses4 != [] && allowedClientCidrs4 != []) ''iifname ${nftInterfaceSet entryInterfaces} ip saddr ${nftAddressSet allowedClientCidrs4} ip daddr ${nftAddressSet listenAddresses4} meta l4proto { tcp, udp } th dport 53 accept''
    ++ lib.optional (listenAddresses6 != [] && allowedClientCidrs6 != []) ''iifname ${nftInterfaceSet entryInterfaces} ip6 saddr ${nftAddressSet allowedClientCidrs6} ip6 daddr ${nftAddressSet listenAddresses6} meta l4proto { tcp, udp } th dport 53 accept''
  );
  firewallRejectRules = lib.concatStringsSep "\n" (
    lib.optional (listenAddresses4 != []) ''iifname != "lo" ip daddr ${nftAddressSet listenAddresses4} meta l4proto { tcp, udp } th dport 53 drop''
    ++ lib.optional (listenAddresses6 != []) ''iifname != "lo" ip6 daddr ${nftAddressSet listenAddresses6} meta l4proto { tcp, udp } th dport 53 drop''
  );
in {
  options.networking.homeRouter.wlt.dns = {
    explicitListenAddresses = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional literal local WG or Nylon addresses on which wlt-dns listens.";
    };

    entryInterfaces = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional WG or Nylon interfaces allowed to enter the DNS frontend.";
    };

    extraAllowedClientCidrs = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional client CIDRs accepted by the edge firewall on DNS entry interfaces.";
    };

    frontDoorBypassRules = lib.mkOption {
      type = types.lines;
      readOnly = true;
      default = frontDoorBypassRules;
      internal = true;
    };

    outputBypassRules = lib.mkOption {
      type = types.lines;
      readOnly = true;
      default = outputBypassRules;
      internal = true;
    };
  };

  config = lib.mkIf homeRouter.enable {
    assertions = [
      {
        assertion = lib.hasAttr ownDomain internalZones;
        message = "networking.homeRouter.dnsmasq.domain must name a canonical networking.internalDns.zones entry.";
      }
      {
        assertion = lib.intersectLists (listenAddresses ++ localBackendAddresses) (publicEndpoints4 ++ publicEndpoints6) == [];
        message = "WLT DNS public endpoints must not overlap listener or local backend addresses.";
      }
    ];

    services.wltDns = {
      enable = true;
      package = config.services.wlt.package;
      configFile = generatedConfigFile;
      uid = dnsUid;
    };

    networking.edgeFirewall.extraInputRules = [
      ''iifname != "lo" meta l4proto { tcp, udp } th dport 1053 drop''
      firewallAcceptRules
      firewallRejectRules
    ];

    networking.policyRouting = {
      ipv4.routingPolicyRules = {
        "49" = map (endpoint: "uidrange ${toString dnsUid}-${toString dnsUid} to ${endpoint} goto 200") publicEndpoints4;
        "250" = map (endpoint: "uidrange ${toString dnsUid}-${toString dnsUid} to ${endpoint} fwmark 0/0xffffff lookup main") publicEndpoints4;
        "251" = map (endpoint: "uidrange ${toString dnsUid}-${toString dnsUid} to ${endpoint} unreachable") publicEndpoints4;
      };
      ipv6.routingPolicyRules = {
        "49" = map (endpoint: "uidrange ${toString dnsUid}-${toString dnsUid} to ${endpoint} goto 200") publicEndpoints6;
        "250" = map (endpoint: "uidrange ${toString dnsUid}-${toString dnsUid} to ${endpoint} fwmark 0/0xffffff lookup main") publicEndpoints6;
        "251" = map (endpoint: "uidrange ${toString dnsUid}-${toString dnsUid} to ${endpoint} unreachable") publicEndpoints6;
      };
    };

    systemd.services.wlt-dns = {
      wants = ["dnsmasq.service"];
      requires = ["policy-routing.service"];
      after = [
        "dnsmasq.service"
        "policy-routing.service"
      ];
      partOf = ["policy-routing.service"];
    };

    services.prometheus.scrapeConfigs = lib.mkIf homeRouter.monitoring.enable [
      {
        job_name = "wlt-dns";
        static_configs = [{targets = ["127.0.0.1:9421"];}];
      }
    ];
  };
}
