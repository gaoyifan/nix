{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.services.nylon;
  types = lib.types;

  nullableString = types.nullOr types.singleLineStr;
  familyType = types.submodule {
    options = {
      ipv4 = lib.mkOption {type = types.bool;};
      ipv6 = lib.mkOption {type = types.bool;};
    };
  };
  exitType = types.submodule {
    options = {
      label = lib.mkOption {type = types.ints.positive;};
      interface = lib.mkOption {type = nullableString;};
      families = lib.mkOption {type = familyType;};
      useDefaultRoute = lib.mkOption {type = types.bool;};
      gateway4 = lib.mkOption {type = nullableString;};
      ipv4Address = lib.mkOption {type = nullableString;};
      ipv6Address = lib.mkOption {type = nullableString;};
    };
  };
  selectorType = types.submodule {
    options = {
      enable = lib.mkOption {type = types.bool;};
      rules = lib.mkOption {
        type = types.submodule {
          options = {
            ipv4 = lib.mkOption {type = types.listOf types.singleLineStr;};
            ipv6 = lib.mkOption {type = types.listOf types.singleLineStr;};
          };
        };
      };
      routes = lib.mkOption {
        type = types.submodule {
          options = {
            ipv4 = lib.mkOption {type = types.listOf types.singleLineStr;};
            ipv6 = lib.mkOption {type = types.listOf types.singleLineStr;};
          };
        };
      };
      ownedTables = lib.mkOption {type = types.listOf types.ints.positive;};
      wlt = lib.mkOption {
        type = types.submodule {
          options = {
            text = lib.mkOption {type = types.lines;};
          };
        };
      };
    };
  };
  compiledType = types.submodule {
    options = {
      central = lib.mkOption {
        type = types.submodule {
          options = {
            text = lib.mkOption {type = types.lines;};
          };
        };
      };
      publicNode = lib.mkOption {
        type = types.submodule {
          options = {
            value = lib.mkOption {type = types.attrs;};
            text = lib.mkOption {type = types.lines;};
          };
        };
      };
      expectedPublicKey = lib.mkOption {type = types.singleLineStr;};
      exits = lib.mkOption {type = types.attrsOf exitType;};
      cloudflareWarp = lib.mkOption {
        type = types.nullOr (types.submodule {
          options = {
            interface = lib.mkOption {type = types.singleLineStr;};
            ipv6Address = lib.mkOption {type = types.singleLineStr;};
            reserved = lib.mkOption {type = types.singleLineStr;};
          };
        });
      };
      selector = lib.mkOption {type = selectorType;};
    };
  };

  nodeValue = cfg.compiled.publicNode.value;
  nodeId = nodeValue.id;
  interfaceName = nodeValue.interface_name;
  udpPort = nodeValue.port;
  mtu = nodeValue.mtu;
  selector = cfg.compiled.selector;
  exitsEnabled = cfg.compiled.exits != {};
  warp = cfg.compiled.cloudflareWarp;
  warpEnabled = warp != null;
  hasWltConfigDirectory = lib.hasAttrByPath ["services" "wlt" "configDirectory"] options;
  hasWltDnsConfigDirectory = lib.hasAttrByPath ["services" "wltDns" "configDirectory"] options;

  centralStore = pkgs.writeText "nylon-central.yaml" cfg.compiled.central.text;
  publicNodeStore = pkgs.writeText "nylon-node-public.yaml" cfg.compiled.publicNode.text;
  selectorWltDirectory = pkgs.writeTextDir "nylon.toml" selector.wlt.text;

  centralSource = "/etc/nylon/central.yaml";
  publicNodeSource = "/etc/nylon/node-public.yaml";
  runtimeDirectory = "/run/nylon";
  runtimeCentral = "${runtimeDirectory}/central.yaml";
  runtimeNode = "${runtimeDirectory}/node.yaml";

  nylonSecret = config.age.secrets."nylon-private-key" or null;
  warpSecrets = builtins.attrValues (lib.filterAttrs (_: secret:
    warpEnabled
    && cfg.cloudflareWarpPrivateKeyFile != null
    && secret.path == cfg.cloudflareWarpPrivateKeyFile)
  config.age.secrets);

  emitRoutes = family: lines:
    lib.concatMapStringsSep "\n" (line: "ip ${family} ${line}") lines;
  tableCleanup =
    lib.concatMapStringsSep "\n" (table: ''
      ip -4 route flush table ${toString table} 2>/dev/null || true
      ip -6 route flush table ${toString table} 2>/dev/null || true
    '')
    selector.ownedTables;
  selectorNamespaceCleanup = ''
    # Tables 5160..5999 are the declared Nylon table namespace. Discovering
    # them from the kernel lets the first Nix generation remove legacy
    # los6/el-103 tables without accepting a mutable batch as desired state.
    for family in -4 -6; do
      ip "$family" route show table all \
        | ${lib.getExe pkgs.gawk} '{ for (i = 1; i < NF; i++) if ($i == "table" && $(i + 1) ~ /^[0-9]+$/ && $(i + 1) >= 5160 && $(i + 1) <= 5999) print $(i + 1) }' \
        | sort -un \
        | while read -r table; do
            ip "$family" route flush table "$table"
          done
    done
  '';

  assembleNode = pkgs.writeShellScript "nylon-assemble-node" ''
    set -euo pipefail
    umask 077

    credential="$CREDENTIALS_DIRECTORY/private-key"
    node_tmp=$(mktemp ${runtimeDirectory}/node.yaml.new.XXXXXX)
    central_tmp=$(mktemp ${runtimeDirectory}/central.yaml.new.XXXXXX)
    cleanup() {
      rm -f "$node_tmp" "$central_tmp"
    }
    trap cleanup EXIT

    if [ ! -s "$credential" ]; then
      echo "Nylon private-key credential is empty" >&2
      exit 1
    fi
    if [ "$(${lib.getExe pkgs.gnused} -n '$=' "$credential")" != 1 ]; then
      echo "Nylon private-key credential must contain exactly one line" >&2
      exit 1
    fi
    private_key=$(${lib.getExe pkgs.gnused} -n '1p' "$credential")
    if ! printf '%s\n' "$private_key" | ${lib.getExe pkgs.gnugrep} -Eq '^[A-Za-z0-9+/]{43}=$'; then
      echo "Nylon private-key credential has an invalid format" >&2
      exit 1
    fi
    if ! derived_public=$(printf '%s\n' "$private_key" | ${lib.getExe pkgs.nylon} pubkey 2>/dev/null); then
      echo "Nylon could not derive a public key from its private-key credential" >&2
      exit 1
    fi
    expected_public=${lib.escapeShellArg cfg.compiled.expectedPublicKey}
    if [ "$derived_public" != "$expected_public" ]; then
      echo "Nylon private key derives to $derived_public, expected $expected_public" >&2
      exit 1
    fi

    install -m 0600 ${publicNodeSource} "$node_tmp"
    printf 'key: %s\n' "$private_key" >> "$node_tmp"
    install -m 0644 ${centralSource} "$central_tmp"
    ${lib.getExe pkgs.nylon} verify "$central_tmp" --node "$node_tmp"

    mv -f "$central_tmp" ${runtimeCentral}
    mv -f "$node_tmp" ${runtimeNode}
  '';

  reloadCentral = pkgs.writeShellScript "nylon-reload-central" ''
    set -euo pipefail

    desired=${centralSource}
    current=${runtimeCentral}
    node=${runtimeNode}
    candidate=$(mktemp ${runtimeDirectory}/central.yaml.reload.XXXXXX)
    previous=$(mktemp ${runtimeDirectory}/central.yaml.previous.XXXXXX)
    cleanup() {
      rm -f "$candidate" "$previous"
    }
    trap cleanup EXIT

    ${lib.getExe pkgs.nylon} verify "$desired" --node "$node"
    install -m 0644 "$desired" "$candidate"
    install -m 0644 "$current" "$previous"
    mv -f "$candidate" "$current"

    reload_json=""
    if reload_json=$(${lib.getExe pkgs.nylon} reload -i ${lib.escapeShellArg interfaceName} --json); then
      result=$(printf '%s\n' "$reload_json" | ${lib.getExe pkgs.jq} -r '.reload.result // empty')
    else
      result=COMMAND_FAILED
    fi
    case "$result" in
      APPLIED|NOOP)
        exit 0
        ;;
    esac

    # The pinned Nylon CLI exits successfully for RESTART_REQUIRED. Restore
    # the prior file and explicitly ask the daemon to reconcile back to it.
    install -m 0644 "$previous" "$candidate"
    mv -f "$candidate" "$current"
    if ! ${lib.getExe pkgs.nylon} reload -i ${lib.escapeShellArg interfaceName} --json >/dev/null; then
      echo "Nylon reload failed and reloading the previous central config also failed" >&2
    fi
    echo "Nylon rejected hot reload with result $result: $reload_json" >&2
    exit 1
  '';

  exitStart =
    lib.concatMapAttrsStringSep "\n" (name: exit: ''
      exit_name=${lib.escapeShellArg name}
      label=${toString exit.label}
      ${
        if exit.useDefaultRoute
        then ''
          default_route=$(ip -4 route show default | ${lib.getExe pkgs.gawk} 'NR == 1 { print; exit }')
          iface=$(printf '%s\n' "$default_route" | ${lib.getExe pkgs.gawk} '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
          gateway=$(printf '%s\n' "$default_route" | ${lib.getExe pkgs.gawk} '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')
          if [ -z "$iface" ]; then
            echo "no IPv4 default-route interface for Nylon exit $exit_name" >&2
            exit 1
          fi
        ''
        else ''
          iface=${lib.escapeShellArg exit.interface}
          gateway=${lib.escapeShellArg exit.gateway4}
        ''
      }
      if ! ip link show dev "$iface" >/dev/null 2>&1; then
        echo "egress interface $iface for Nylon exit $exit_name is absent" >&2
        exit 1
      fi
      ${lib.optionalString (!exit.useDefaultRoute && exit.gateway4 == null) ''
        default_route=$(ip -4 route show default dev "$iface" | ${lib.getExe pkgs.gawk} 'NR == 1 { print; exit }')
        gateway=$(printf '%s\n' "$default_route" | ${lib.getExe pkgs.gawk} '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')
        if [ -z "$default_route" ] && ! ip -o link show dev "$iface" | grep -qw POINTOPOINT; then
          echo "no IPv4 default route or point-to-point link for Nylon exit $exit_name on $iface; configure gateway4 explicitly" >&2
          exit 1
        fi
      ''}

      printf 'mpls-route\t%s\n' "$label" >> "$state"
      if [ -n "$gateway" ]; then
        ip -f mpls route replace "$label" via inet "$gateway" dev "$iface"
      else
        ip -f mpls route replace "$label" dev "$iface"
      fi

      printf 'ingress-filter\t%s\n' "$label" >> "$state"
      mark=$((0x10000 + label))
      tc filter replace dev ${lib.escapeShellArg interfaceName} ingress protocol mpls_uc pref "$label" \
        flower mpls_label "$label" action skbedit mark "$mark"

      ensure_clsact "$iface"
      ${lib.optionalString exit.families.ipv4 ''
        ip4=${lib.escapeShellArg exit.ipv4Address}
        if [ -z "$ip4" ]; then
          ip4=$(ip -o -4 addr show dev "$iface" scope global | ${lib.getExe pkgs.gawk} 'NR == 1 { split($4, address, "/"); print address[1] }')
        fi
        if [ -z "$ip4" ]; then
          echo "Nylon exit $exit_name declares IPv4 but $iface has no IPv4 SNAT address" >&2
          exit 1
        fi
        printf 'egress-filter4\t%s\t%s\n' "$iface" "$label" >> "$state"
        tc filter replace dev "$iface" egress protocol ip pref "$label" handle "$mark" fw \
          action ct commit nat src addr "$ip4" pipe
        echo "nylon-exit $exit_name: IPv4 SNAT to $ip4 on $iface"
      ''}
      ${lib.optionalString exit.families.ipv6 ''
        ip6=${lib.escapeShellArg exit.ipv6Address}
        if [ -z "$ip6" ]; then
          ip6=$(ip -o -6 addr show dev "$iface" scope global | ${lib.getExe pkgs.gawk} 'NR == 1 { split($4, address, "/"); print address[1] }')
        fi
        if [ -z "$ip6" ]; then
          echo "Nylon exit $exit_name declares IPv6 but $iface has no IPv6 SNAT address" >&2
          exit 1
        fi
        pref=$((label + 1000))
        printf 'egress-filter6\t%s\t%s\n' "$iface" "$pref" >> "$state"
        tc filter replace dev "$iface" egress protocol ipv6 pref "$pref" handle "$mark" fw \
          action ct commit nat src addr "$ip6" pipe
        echo "nylon-exit $exit_name: IPv6 SNAT to $ip6 on $iface"
      ''}
      echo "nylon-exit $exit_name: label $label via $iface"
    '')
    cfg.compiled.exits;

  exitCleanup = ''
    state=/run/nylon-exit/owned
    if [ ! -r "$state" ]; then
      exit 0
    fi

    while IFS=$'\t' read -r kind first second; do
      case "$kind" in
        mpls-input)
          if [ -e "/proc/sys/net/mpls/conf/$first/input" ]; then
            echo 0 > "/proc/sys/net/mpls/conf/$first/input"
          fi
          ;;
        mpls-route)
          ip -f mpls route del "$first" 2>/dev/null || true
          ;;
        ingress-filter)
          tc filter del dev ${lib.escapeShellArg interfaceName} ingress protocol mpls_uc pref "$first" 2>/dev/null || true
          ;;
        egress-filter4)
          tc filter del dev "$first" egress protocol ip pref "$second" 2>/dev/null || true
          ;;
        egress-filter6)
          tc filter del dev "$first" egress protocol ipv6 pref "$second" 2>/dev/null || true
          ;;
      esac
    done < "$state"

    while IFS=$'\t' read -r kind iface _; do
      if [ "$kind" = qdisc ]; then
        tc qdisc del dev "$iface" clsact 2>/dev/null || true
      fi
    done < "$state"
    rm -f "$state"
  '';

  selectorStart =
    if selector.enable
    then ''
      for _ in {1..50}; do
        ip -brief link show dev ${lib.escapeShellArg interfaceName} 2>/dev/null | grep -qw LOWER_UP && break
        sleep 0.2
      done
      if ! ip -brief link show dev ${lib.escapeShellArg interfaceName} | grep -qw LOWER_UP; then
        echo "${interfaceName} not LOWER_UP; cannot apply Nylon selector routes" >&2
        exit 1
      fi

      ${selectorNamespaceCleanup}

      ${lib.optionalString (selector.routes.ipv4 != []) ''
        ${emitRoutes "-4" selector.routes.ipv4}
      ''}
      ${lib.optionalString (selector.routes.ipv6 != []) ''
        ${emitRoutes "-6" selector.routes.ipv6}
      ''}
    ''
    else ''
      # Priority 200 is networking.policyRouting's dedicated wltOutlet bucket.
      while ip -4 rule del pref 200 2>/dev/null; do :; done
      while ip -6 rule del pref 200 2>/dev/null; do :; done

      ${selectorNamespaceCleanup}
    '';
in {
  disabledModules = ["services/networking/nylon.nix"];
  imports = [../optional/policy-routing.nix];

  options.services.nylon = {
    enable = lib.mkEnableOption "the Nix-compiled Nylon mesh runtime";

    compiled = lib.mkOption {
      type = compiledType;
      description = "One per-host projection produced by nixos/nylon/compile.nix.";
    };

    privateKeyFile = lib.mkOption {
      type = types.str;
      default = "/run/agenix/nylon-private-key";
      description = "Runtime path of the agenix-decrypted Nylon private key.";
    };

    cloudflareWarpPrivateKeyFile = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime path of the agenix-decrypted Cloudflare WARP WireGuard private key.";
    };

    udpPort = lib.mkOption {
      type = types.port;
      readOnly = true;
      default = udpPort;
      description = "Compiled Nylon UDP port, exposed for firewall modules.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = lib.hasSuffix "\n" cfg.compiled.publicNode.text;
          message = "services.nylon.compiled.publicNode.text must end in a newline for runtime key assembly.";
        }
        {
          assertion =
            !(lib.hasPrefix "key:" cfg.compiled.publicNode.text
              || lib.hasInfix "\nkey:" cfg.compiled.publicNode.text);
          message = "services.nylon.compiled.publicNode.text must not contain a private key field.";
        }
        {
          assertion = nodeId == config.networking.hostName;
          message = "compiled Nylon node id '${nodeId}' must equal networking.hostName '${config.networking.hostName}'.";
        }
        {
          assertion = interfaceName == "nylon0";
          message = "the current Nylon MPLS/WLT datapath requires interface_name=nylon0.";
        }
        {
          assertion = nylonSecret != null && nylonSecret.path == cfg.privateKeyFile;
          message = "services.nylon.privateKeyFile must be provided by age.secrets.nylon-private-key.";
        }
        {
          assertion = !lib.hasPrefix "/nix/store/" cfg.privateKeyFile;
          message = "the Nylon private key must not come from the Nix store.";
        }
        {
          assertion = warpEnabled == (cfg.cloudflareWarpPrivateKeyFile != null);
          message = "cloudflareWarpPrivateKeyFile must be set exactly when the compiled host has a Cloudflare WARP projection.";
        }
        {
          assertion = !warpEnabled || builtins.length warpSecrets == 1;
          message = "cloudflareWarpPrivateKeyFile must match exactly one agenix secret path.";
        }
        {
          assertion =
            !warpEnabled
            || !lib.hasPrefix "/nix/store/" cfg.cloudflareWarpPrivateKeyFile;
          message = "the Cloudflare WARP private key must not come from the Nix store.";
        }
        {
          assertion =
            !selector.enable
            || (hasWltConfigDirectory && config.services.wlt.enable);
          message = "a compiled Nylon selector requires an enabled WLT NixOS module.";
        }
      ];

      boot.kernelModules = [
        "act_ct"
        "act_skbedit"
        "cls_flower"
        "mpls_router"
        "mpls_iptunnel"
      ];
      boot.kernel.sysctl."net.mpls.platform_labels" = 256;

      environment = {
        etc = {
          "nylon/central.yaml".source = centralStore;
          "nylon/node-public.yaml".source = publicNodeStore;
        };
        systemPackages = [pkgs.nylon];
      };

      networking.nftables = {
        enable = true;
        tables.nylon = {
          family = "inet";
          content = ''
            chain prerouting-mss {
              type filter hook prerouting priority mangle; policy accept;
              iifname "${interfaceName}" tcp flags syn tcp option maxseg size > ${toString (mtu - 8 - 60)} tcp option maxseg size set ${toString (mtu - 8 - 60)}
            }
          '';
        };
      };

      systemd.services = {
        nylon = {
          description = "Nylon mesh router";
          wantedBy = ["multi-user.target"];
          wants = ["network-online.target"];
          after = [
            "network-online.target"
            "agenix-install-secrets.service"
          ];
          path = [pkgs.iproute2];
          restartTriggers =
            [
              centralStore
              publicNodeStore
            ]
            ++ lib.optional (nylonSecret != null) nylonSecret.file;
          serviceConfig = {
            ExecStartPre = assembleNode;
            ExecStart = "${lib.getExe pkgs.nylon} run -c ${runtimeCentral} -n ${runtimeNode}";
            ExecReload = reloadCentral;
            LoadCredential = "private-key:${cfg.privateKeyFile}";
            WorkingDirectory = runtimeDirectory;
            RuntimeDirectory = "nylon";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";
            Restart = "on-failure";
            RestartSec = "5s";
          };
        };

        nylon-routes = {
          description = "Exact Nylon selector route reconciliation";
          wantedBy = ["multi-user.target"];
          requires = ["nylon.service"];
          after =
            ["nylon.service"]
            ++ lib.optional selector.enable "policy-routing.service";
          partOf = ["nylon.service"];
          path = [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.iproute2
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = "10s";
          };
          script = selectorStart;
          postStop = lib.optionalString selector.enable tableCleanup;
        };
      };
    }

    (lib.mkIf selector.enable {
      networking.nftables.tables.nylon.content = ''
        chain overlay-nat-postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "${interfaceName}" ip saddr != 10.250.10.0/24 masquerade
          oifname "${interfaceName}" ip6 saddr != fd10:250:10::/64 masquerade
        }
      '';
    })

    (lib.mkIf selector.enable (lib.mkMerge [
      {
        networking.policyRouting = {
          enable = true;
          ipv4.routingPolicyRules.wltOutlet = selector.rules.ipv4;
          ipv6.routingPolicyRules.wltOutlet = selector.rules.ipv6;
        };
      }
      (lib.optionalAttrs hasWltConfigDirectory {
        services.wlt.configDirectory = lib.mkForce selectorWltDirectory;
      })
      (lib.optionalAttrs hasWltDnsConfigDirectory (lib.mkIf config.services.wltDns.enable {
        services.wltDns.configDirectory = selectorWltDirectory;
      }))
    ]))

    (lib.mkIf exitsEnabled {
      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = true;
        "net.ipv6.conf.all.forwarding" = true;
      };

      networking.nftables.tables.nylon.content = ''
        chain exit-track {
          type filter hook prerouting priority -300; policy accept;
          ct state established,related accept
        }
        chain exit-nat-prerouting {
          type nat hook prerouting priority -90; policy accept;
        }
        chain exit-nat-postrouting {
          type nat hook postrouting priority 90; policy accept;
        }
      '';

      systemd.services.nylon-exit = {
        description = "Nylon MPLS exits: static LSPs and egress SNAT";
        wantedBy = ["multi-user.target"];
        requires =
          ["nylon.service"]
          ++ lib.optional warpEnabled "nylon-warp-reconfigure.service";
        after =
          ["nylon.service"]
          ++ lib.optional warpEnabled "nylon-warp-reconfigure.service";
        partOf =
          ["nylon.service"]
          ++ lib.optional warpEnabled "nylon-warp-reconfigure.service";
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.iproute2
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = "nylon-exit";
          RuntimeDirectoryMode = "0700";
          Restart = "on-failure";
          RestartSec = "10s";
        };
        script = ''
          state=/run/nylon-exit/owned
          : > "$state"
          chmod 0600 "$state"

          for _ in {1..50}; do
            ip link show dev ${lib.escapeShellArg interfaceName} >/dev/null 2>&1 && break
            sleep 0.2
          done
          if ! ip link show dev ${lib.escapeShellArg interfaceName} >/dev/null 2>&1; then
            echo "${interfaceName} absent; cannot configure Nylon exits" >&2
            exit 1
          fi

          ensure_clsact() {
            local iface=$1
            if ! tc qdisc show dev "$iface" | grep -q 'qdisc clsact '; then
              tc qdisc add dev "$iface" clsact
              printf 'qdisc\t%s\n' "$iface" >> "$state"
            fi
          }

          printf 'mpls-input\t%s\n' ${lib.escapeShellArg interfaceName} >> "$state"
          echo 1 > /proc/sys/net/mpls/conf/${interfaceName}/input
          ensure_clsact ${lib.escapeShellArg interfaceName}

          ${exitStart}
        '';
        postStop = exitCleanup;
      };
    })

    (lib.mkIf warpEnabled {
      networking = {
        nftables.tables.nylon.content = ''
          set warp_endpoints_v4 {
            type ipv4_addr
            elements = { 162.159.192.1, 162.159.192.2, 162.159.192.3, 162.159.192.4, 162.159.192.5, 162.159.193.1, 162.159.193.2, 162.159.193.3, 162.159.193.4, 162.159.193.5 }
          }
          set warp_endpoints_v6 {
            type ipv6_addr
            elements = { 2606:4700:d0::a29f:c001, 2606:4700:d0::a29f:c002, 2606:4700:d0::a29f:c003, 2606:4700:d0::a29f:c004, 2606:4700:d0::a29f:c005 }
          }
          set warp_udp_ports {
            type inet_service
            elements = { 500, 1701, 2408, 4500 }
          }
          chain warp-in {
            type filter hook input priority mangle; policy accept;
            ip saddr @warp_endpoints_v4 udp sport @warp_udp_ports @th,72,24 set 0x0
            ip6 saddr @warp_endpoints_v6 udp sport @warp_udp_ports @th,72,24 set 0x0
          }
          chain warp-out {
            type filter hook output priority mangle; policy accept;
            ip daddr @warp_endpoints_v4 udp dport @warp_udp_ports @th,72,24 set ${warp.reserved}
            ip6 daddr @warp_endpoints_v6 udp dport @warp_udp_ports @th,72,24 set ${warp.reserved}
          }
        '';

        wireguard.interfaces.${warp.interface} = {
          ips = [
            "172.16.0.2/32"
            "${warp.ipv6Address}/128"
          ];
          privateKeyFile = cfg.cloudflareWarpPrivateKeyFile;
          allowedIPsAsRoutes = false;
          peers = [
            {
              publicKey = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";
              allowedIPs = [
                "0.0.0.0/0"
                "::/0"
              ];
              endpoint = "162.159.192.1:2408";
              persistentKeepalive = 25;
            }
          ];
        };
      };

      systemd.services.nylon-warp-reconfigure = {
        description = "Reconcile the Nylon Cloudflare WARP netdev";
        wantedBy = ["multi-user.target"];
        requires = ["systemd-networkd.service"];
        after = [
          "systemd-networkd.service"
          "agenix-install-secrets.service"
        ];
        path = [
          pkgs.coreutils
          pkgs.iproute2
        ];
        restartTriggers = map (secret: secret.file) warpSecrets;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${lib.getExe' pkgs.systemd "networkctl"} delete ${lib.escapeShellArg warp.interface} 2>/dev/null || true
          ${lib.getExe' pkgs.systemd "networkctl"} reload
          for _ in {1..50}; do
            ip link show dev ${lib.escapeShellArg warp.interface} >/dev/null 2>&1 && break
            sleep 0.2
          done
          if ! ip link show dev ${lib.escapeShellArg warp.interface} >/dev/null 2>&1; then
            echo "Cloudflare WARP interface ${warp.interface} was not recreated by systemd-networkd" >&2
            exit 1
          fi
          ${lib.getExe' pkgs.systemd "networkctl"} reconfigure ${lib.escapeShellArg warp.interface}
        '';
      };
    })
  ]);
}
