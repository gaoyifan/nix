# Reusable NixOS module for the WLT outlet selector
# (https://github.com/gaoyifan/wlt).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.wlt;

  lanInterfaceSet = "{ ${lib.concatMapStringsSep ", " (name: "\"${name}\"") cfg.lanInterfaces} }";
  defaultOutletRules = lib.optionalString (cfg.defaultOutletMark.ipv4 != null || cfg.defaultOutletMark.ipv6 != null) ''
    # Optional default overseas egress for LAN clients without an explicit
    # selection. null disables the implicit default for that family.
    ${lib.optionalString (cfg.defaultOutletMark.ipv4 != null) ''iifname ${lanInterfaceSet} ip daddr != @cn meta mark 0 meta mark set ${cfg.defaultOutletMark.ipv4}''}
    ${lib.optionalString (cfg.defaultOutletMark.ipv6 != null) ''iifname ${lanInterfaceSet} ip6 daddr != @cn6 meta mark 0 meta mark set ${cfg.defaultOutletMark.ipv6}''}
  '';

  wltSecrets = config.services.secrets.nixos.wlt;
  runtimeDir = "/run/wlt";
  sshHostKeyRuntime = "${runtimeDir}/ssh_host_key";
  tlsCertRuntime = "${runtimeDir}/tls/server.pem";
  tlsKeyRuntime = "${runtimeDir}/tls/server-key.pem";

  snapshotFile = "${cfg.persistDir}/wlt_src2mark.conf";

  geoSets = pkgs.nft-geo-sets;

  # Base config; operators can drop extra outlet fragments into configD.
  wltConfig = pkgs.writeText "wlt-config.toml" ''
    time_limits = [1, 4, 10, 24, 0] # 1小时, 4小时, 10小时, 24小时, 永久

    # Services are enabled by section presence in the Rust wlt binary.
    [web]
    # Bind explicitly to the lo portal addresses: this host runs no packet
    # filter, so do not expose the portal on every interface.
    listen = ["${cfg.portal.ipv4Address}:80", "[${cfg.portal.ipv6Address}]:80"]

    [web.https]
    listen = ["${cfg.portal.ipv4Address}:443", "[${cfg.portal.ipv6Address}]:443"]
    cert = "/data/tls/server.pem"
    key = "/data/tls/server-key.pem"

    # SSH TUI for outlet selection (ssh -p 2222 <host>); the host key persists
    # across restarts.
    [ssh]
    listen = ["[::]:2222"]
    host_key = "/data/ssh_host_key"

    [persist]
    path = "/etc/nftables/wlt_src2mark.conf"
    interval = 300

    [nftables]
    family = "inet"
    table = "wlt"
    map = "src2mark"        # IPv4 client src -> mark
    map_v6 = "src2mark6"    # IPv6 client src -> mark

    [portal]
    domain = "${cfg.domain}"
    v4_host = "${cfg.portal.v4Host}"
    v6_host = "${cfg.portal.v6Host}"
    cors_domain = "${cfg.portal.corsDomain}"

    [[outlet_groups]]
    title = "国内出口"
    mask = 0xFF00
    [outlet_groups.outlets]
    "默认" = 0x0
    [outlet_groups.outlets_v6]
    "默认" = 0x0
    "禁用 IPv6" = 0xff00

    [[outlet_groups]]
    title = "海外出口"
    cn_last = true
    mask = 0xFF
    [outlet_groups.outlets]
    "默认" = 0x0
    [outlet_groups.outlets_v6]
    "默认" = 0x0
    "禁用 IPv6" = 0xff
  '';
in {
  options.services.wlt = {
    enable = lib.mkEnableOption "WLT outlet selector";

    image = lib.mkOption {
      type = lib.types.str;
      # Rust rewrite at upstream 6acf14d. Pin the multi-arch image index
      # instead of tracking latest/main so rebuilds do not drift.
      default = "ghcr.io/gaoyifan/wlt@sha256:f805f9ec0b5ffae8dddcfd9666707a6785ceccd204b485543928316b3f2dcf6d";
      description = "OCI image used for the WLT service.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      example = "gaof.net";
      description = "Single public domain used by the WLT portal.";
    };

    portal = {
      ipv4Address = lib.mkOption {
        type = lib.types.str;
        default = "198.18.255.254";
        description = "IPv4 portal address bound on loopback.";
      };
      ipv6Address = lib.mkOption {
        type = lib.types.str;
        default = "2001:2::ffff";
        description = "IPv6 portal address bound on loopback.";
      };
      v4Host = lib.mkOption {
        type = lib.types.str;
        default = "wlt-ipv4.${cfg.domain}";
        defaultText = lib.literalExpression ''"wlt-ipv4.''${config.services.wlt.domain}"'';
        description = "IPv4 API hostname.";
      };
      v6Host = lib.mkOption {
        type = lib.types.str;
        default = "wlt-ipv6.${cfg.domain}";
        defaultText = lib.literalExpression ''"wlt-ipv6.''${config.services.wlt.domain}"'';
        description = "IPv6 API hostname.";
      };
      corsDomain = lib.mkOption {
        type = lib.types.str;
        default = cfg.domain;
        defaultText = lib.literalExpression "config.services.wlt.domain";
        description = "CORS domain accepted by the portal API.";
      };
    };

    lanInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.attrNames config.networking.homeRouter.bridges;
      defaultText = lib.literalExpression "lib.attrNames config.networking.homeRouter.bridges";
      description = "LAN interfaces whose unselected overseas traffic gets default WLT marks.";
    };

    defaultOutletMark = {
      ipv4 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "0x10";
        description = "Default IPv4 overseas outlet mark for LAN clients. null disables the default.";
      };
      ipv6 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "0x20";
        description = "Default IPv6 overseas outlet mark for LAN clients. null disables the default.";
      };
    };

    configD = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/wlt/config.d";
      description = "Directory for additional WLT config fragments.";
    };

    persistDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/wlt/persist";
      description = "Directory used by WLT to persist nftables selections.";
    };

    sshHostKeyFile = lib.mkOption {
      type = lib.types.path;
      default = wltSecrets.sshHostKeyFile;
      description = "Shared SSH host private key for WLT.";
    };

    tls = {
      certFile = lib.mkOption {
        type = lib.types.path;
        default = wltSecrets.tls.certFile;
        description = "WLT HTTPS server certificate.";
      };
      keyFile = lib.mkOption {
        type = lib.types.path;
        default = wltSecrets.tls.keyFile;
        description = "WLT HTTPS server private key.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.lanInterfaces != [];
        message = "services.wlt.lanInterfaces must be set, or networking.homeRouter.bridges must define at least one bridge.";
      }
    ];

    # Containers run with host networking only: podman is daemonless and its
    # netavark firewall driver only installs rules for bridged networks, so
    # nftables owns the ruleset alone.
    virtualisation.podman.enable = true;
    networking.nftables.enable = true;

    virtualisation.oci-containers = {
      backend = "podman";
      containers.wlt = {
        image = cfg.image;
        volumes = [
          "${wltConfig}:/app/config.toml:ro"
          "${cfg.configD}:/app/config.d:ro"
          "${cfg.persistDir}:/etc/nftables"
          "${sshHostKeyRuntime}:/data/ssh_host_key:ro"
          "${tlsCertRuntime}:/data/tls/server.pem:ro"
          "${tlsKeyRuntime}:/data/tls/server-key.pem:ro"
        ];
        extraOptions = [
          "--network=host"
          "--cap-add=NET_ADMIN"
        ];
      };
    };

    systemd.services.podman-wlt.serviceConfig = {
      RuntimeDirectory = lib.mkForce "wlt";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "wlt-install-runtime-secrets" ''
          set -euo pipefail

          ${pkgs.coreutils}/bin/install -d -m 0700 ${runtimeDir}/tls
          ${pkgs.coreutils}/bin/install -m 0600 ${cfg.sshHostKeyFile} ${sshHostKeyRuntime}
          ${pkgs.coreutils}/bin/install -m 0644 ${cfg.tls.certFile} ${tlsCertRuntime}
          ${pkgs.coreutils}/bin/install -m 0600 ${cfg.tls.keyFile} ${tlsKeyRuntime}
        '')
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.configD} 0755 root root -"
      "d ${cfg.persistDir} 0755 root root -"
      # The ruleset includes the snapshot, so it must exist before nftables
      # loads (wlt-persist overwrites it every 5 minutes).
      "f ${snapshotFile} 0644 root root -"
    ];

    # Shared portal addresses on lo, managed declaratively by networkd (the
    # loopback 127.0.0.1/::1 addresses are kernel-owned and left alone).
    systemd.network.networks."60-lo-wlt-portal" = {
      matchConfig.Name = "lo";
      address = [
        "${cfg.portal.ipv4Address}/32"
        "${cfg.portal.ipv6Address}/128"
      ];
      linkConfig.RequiredForOnline = "no";
    };

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
          # src2mark: high byte selects the CN outlet, low byte the overseas one
          ip daddr @cn    meta mark set ip saddr map @src2mark meta mark set mark >> 8
          ip daddr != @cn meta mark set ip saddr map @src2mark meta mark set mark & 0xff
          ip6 daddr @cn6    meta mark set ip6 saddr map @src2mark6 meta mark set mark >> 8
          ip6 daddr != @cn6 meta mark set ip6 saddr map @src2mark6 meta mark set mark & 0xff
          ${defaultOutletRules}
        }

        # The SSH selector (wlt-ssh) listens on 2222; let LAN clients reach it
        # on the portal addresses' plain SSH port.
        chain portal-dnat {
          type nat hook prerouting priority dstnat; policy accept;
          ip daddr ${cfg.portal.ipv4Address} tcp dport 22 dnat ip to ${cfg.portal.ipv4Address}:2222
          ip6 daddr ${cfg.portal.ipv6Address} tcp dport 22 dnat ip6 to [${cfg.portal.ipv6Address}]:2222
        }
      '';
    };

    # Restore the persisted outlet selections after the table is recreated.
    networking.nftables.ruleset = ''
      include "${snapshotFile}"
    '';

    # The snapshot lives outside the store; drop its include for the sandboxed
    # build-time `nft --check` (libredirect does not catch nft's include open).
    networking.nftables.preCheckRuleset = ''
      sed 's|include "${snapshotFile}"||' -i ruleset.conf
    '';

    systemd.services.wlt-ipv6-disable-route = {
      description = "WLT disabled IPv6 route table";
      wantedBy = ["multi-user.target"];
      path = [pkgs.iproute2];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # "禁用 IPv6" outlet: final fwmark 0xff sends v6 to an unreachable table.
        ip -6 route replace unreachable default table 5255
      '';
    };
  };
}
