# WLT is an internal homeRouter capability. Its implementation constants stay
# behind networking.homeRouter.wlt's small interface.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  homeRouter = config.networking.homeRouter;
  cfg = homeRouter.wlt;
  lanInterfaceSet = "{ ${lib.concatMapStringsSep ", " (name: "\"${name}\"") homeRouter.internalInterfaces} }";
  disabledIpv6Mark = "0xfff";
  disabledIpv6Table = 4095;
  defaultOutletRules = ''
    ${lib.optionalString (cfg.defaultOutlet.ipv4Mark != null) ''fib saddr oifname ${lanInterfaceSet} ip daddr != @cn meta mark 0 meta mark set ${cfg.defaultOutlet.ipv4Mark}''}
    ${lib.optionalString (cfg.defaultOutlet.ipv6 == "disabled") ''fib saddr oifname ${lanInterfaceSet} ip6 daddr != @cn6 meta mark 0 meta mark set ${disabledIpv6Mark}''}
  '';

  configD = "/var/lib/wlt/config.d";
  persistDir = "/var/lib/wlt/persist";
  snapshotFile = "${persistDir}/wlt_src2mark-v2.conf";
  wltSecrets = {
    sshHostKeyFile = "/run/agenix/wlt-ssh-host-key";
    tls = {
      certFile = config.services.secrets.filesDir + "/nixos/wlt-server.pem";
      keyFile = "/run/agenix/wlt-server-key";
    };
  };
  portalIpv4 = homeRouter.serviceAddresses.ipv4;
  portalIpv6 = homeRouter.serviceAddresses.ipv6;
  geoSets = pkgs.nft-geo-sets;

  wltConfig = pkgs.writeText "wlt-config.toml" ''
    time_limits = [1, 4, 10, 24, 0]

    [web]
    listen = ["${portalIpv4}:80", "[${portalIpv6}]:80"]

    [web.https]
    listen = ["${portalIpv4}:443", "[${portalIpv6}]:443"]
    cert = "${wltSecrets.tls.certFile}"
    key = "${wltSecrets.tls.keyFile}"

    [ssh]
    listen = ["[::]:2222"]
    host_key = "${wltSecrets.sshHostKeyFile}"

    [persist]
    path = "${snapshotFile}"
    interval = 300

    [nftables]
    family = "inet"
    table = "wlt"
    map = "src2mark"
    map_v6 = "src2mark6"

    [portal]
    domain = "${cfg.domain}"
    v4_host = "wlt-ipv4.${cfg.domain}"
    v6_host = "wlt-ipv6.${cfg.domain}"
    cors_domain = "${cfg.domain}"

    [[outlet_groups]]
    title = "国内出口"
    mask = 0xFFF000
    [outlet_groups.outlets]
    "默认" = 0x0
    [outlet_groups.outlets_v6]
    "默认" = 0x0
    "禁用 IPv6" = 0xfff000

    [[outlet_groups]]
    title = "海外出口"
    cn_last = true
    mask = 0xFFF
    [outlet_groups.outlets]
    "默认" = 0x0
    [outlet_groups.outlets_v6]
    "默认" = 0x0
    "禁用 IPv6" = 0xfff
  '';
in {
  imports = [inputs.wlt.nixosModules.default];

  options.networking.homeRouter.wlt = {
    enable = lib.mkEnableOption "WLT outlet selector";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "gaof.net";
      description = "Public domain used by the WLT portal.";
    };
    defaultOutlet = {
      ipv4Mark = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default IPv4 overseas outlet mark for internal LAN clients.";
      };
      ipv6 = lib.mkOption {
        type = lib.types.enum ["default" "disabled"];
        default = "default";
        description = "Default IPv6 overseas behavior for internal LAN clients.";
      };
    };
  };

  config = lib.mkIf (homeRouter.enable && cfg.enable) (lib.mkMerge [
    {
      assertions = [
        {
          assertion = homeRouter.internalInterfaces != [];
          message = "networking.homeRouter.wlt requires at least one non-guest LAN.";
        }
      ];

      services.wlt = {
        enable = true;
        configFile = wltConfig;
        configDirectory = configD;
      };

      systemd.tmpfiles.rules = [
        "d ${configD} 0755 root root -"
        "d ${persistDir} 0755 root root -"
        "f ${snapshotFile} 0644 root root -"
      ];

      networking.nftables.tables.wlt = {
        family = "inet";
        content = ''
          include "${geoSets}/set-cn.conf"
          include "${geoSets}/set-cn6.conf"

          map src2mark {
            type ipv4_addr : mark
            flags interval, timeout
          }
          map src2mark6 {
            type ipv6_addr : mark
            flags timeout
          }

          chain prerouting {
            type filter hook prerouting priority mangle - 1; policy accept;
            ip daddr @cn    meta mark set ip saddr map @src2mark meta mark set mark >> 12
            ip daddr != @cn meta mark set ip saddr map @src2mark meta mark set mark & 0xfff
            ip6 daddr @cn6    meta mark set ip6 saddr map @src2mark6 meta mark set mark >> 12
            ip6 daddr != @cn6 meta mark set ip6 saddr map @src2mark6 meta mark set mark & 0xfff
            ${defaultOutletRules}
          }

          chain portal-dnat {
            type nat hook prerouting priority dstnat; policy accept;
            ip daddr ${portalIpv4} tcp dport 22 dnat ip to ${portalIpv4}:2222
            ip6 daddr ${portalIpv6} tcp dport 22 dnat ip6 to [${portalIpv6}]:2222
          }
        '';
      };

      networking.nftables.ruleset = ''
        include "${snapshotFile}"
      '';

      networking.nftables.preCheckRuleset = ''
        sed 's|include "${snapshotFile}"||' -i ruleset.conf
      '';
    }

    (lib.mkIf (cfg.defaultOutlet.ipv6 == "disabled") {
      networking.policyRouting = {
        ipv6.routingPolicyRules.wltOutlet = lib.mkBefore [
          "fwmark ${disabledIpv6Mark}/${disabledIpv6Mark} lookup ${toString disabledIpv6Table}"
        ];
      };

      systemd.network.networks."60-lo-host-services".routes = [
        {
          Destination = "::/0";
          Table = toString disabledIpv6Table;
          Type = "unreachable";
        }
      ];
    })
  ]);
}
