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
  disabledIpv6Mark = "0xfff";
  disabledIpv6Table = 4095;

  persistDir = "/var/lib/wlt/persist";
  snapshotFile = "${persistDir}/wlt_src2mark-v3.conf";
  portalIpv4 = homeRouter.serviceAddresses.ipv4;
  portalIpv6 = homeRouter.serviceAddresses.ipv6;

  wltConfig = pkgs.writeText "wlt-config.toml" ''
    time_limits = [1, 4, 10, 24, 0]

    [web]
    listen = ["${portalIpv4}:80", "[${portalIpv6}]:80"]

    [web.https]
    listen = ["${portalIpv4}:443", "[${portalIpv6}]:443"]
    cert = "${config.services.secrets.filesDir}/nixos/wlt-server.pem"
    key = "/run/agenix/wlt-server-key"

    [ssh]
    listen = ["[::]:2222"]
    host_key = "/run/agenix/wlt-ssh-host-key"

    [persist]
    path = "${snapshotFile}"
    interval = 300

    [nftables]
    family = "inet"
    table = "home-router"
    map = "src2mark"
    map_v6 = "src2mark6"

    [portal]
    domain = "gaof.net"
    v4_host = "wlt-ipv4.gaof.net"
    v6_host = "wlt-ipv6.gaof.net"
    cors_domain = "gaof.net"

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
        configDirectory = null;
      };

      age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
        wlt-server-key.file = config.services.secrets.filesDir + "/nixos/wlt-server-key.pem.age";
        wlt-ssh-host-key.file = config.services.secrets.filesDir + "/nixos/wlt-ssh-host-key.age";
      };

      systemd.tmpfiles.rules = [
        "d ${persistDir} 0755 root root -"
        "f ${snapshotFile} 0644 root root -"
      ];

      networking.nftables.tables.home-router.content = ''
        map src2mark {
          type ipv4_addr : mark
          flags interval, timeout
        }
        map src2mark6 {
          type ipv6_addr : mark
          flags timeout
        }

        chain wlt-prerouting {
          type filter hook prerouting priority mangle - 1; policy accept;
          ip daddr @cn    meta mark set ip saddr map @src2mark meta mark set mark >> 12
          ip daddr != @cn meta mark set ip saddr map @src2mark meta mark set mark & 0xfff
          ip6 daddr @cn6    meta mark set ip6 saddr map @src2mark6 meta mark set mark >> 12
          ip6 daddr != @cn6 meta mark set ip6 saddr map @src2mark6 meta mark set mark & 0xfff
        }

        chain wlt-portal-dnat {
          type nat hook prerouting priority dstnat; policy accept;
          ip daddr ${portalIpv4} tcp dport 22 dnat ip to ${portalIpv4}:2222
          ip6 daddr ${portalIpv6} tcp dport 22 dnat ip6 to [${portalIpv6}]:2222
        }
      '';

      networking.nftables.ruleset = ''
        include "${snapshotFile}"
      '';

      networking.nftables.preCheckRuleset = ''
        sed 's|include "${snapshotFile}"||' -i ruleset.conf
      '';
    }

    {
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
    }
  ]);
}
