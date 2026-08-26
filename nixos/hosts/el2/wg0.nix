{pkgs, ...}: let
  stateDir = "/var/lib/wireguard";
  userDir = "${stateDir}/user";
  newClient = pkgs.writeShellScript "wg0-new-client" ''
    set -euo pipefail

    base=${stateDir}
    cd "$base/user"
    user=$1
    umask 077

    if [ "$#" -ge 2 ]; then
      serial=$2
    elif [ -f "$user.serial" ]; then
      serial=$(<"$user.serial")
    else
      serial=$(<serial)
      serial=$((serial + 1))
      update_serial=1
    fi

    if [ ! -f "$user.priv" ]; then
      wg genkey | tee "$user.priv" | wg pubkey >"$user.pub"
    fi

    wg set wg0 peer "$(<"$user.pub")" allowed-ips "100.64.110.$serial/32"

    tee "$user.conf" <<EOF
    [Interface]
    PrivateKey = $(<"$user.priv")
    Address = 100.64.110.$serial/24
    DNS = 100.64.110.254
    MTU = 1392

    [Peer]
    PublicKey = $(wg pubkey <"$base/server.key")
    Endpoint = 202.38.93.98:2197
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    EOF

    wg-quick save "$base/wg0.conf"
    systemctl restart wg0-forward-firewall.service
    echo "$serial" >"$user.serial"
    if [ "''${update_serial:-}" = 1 ]; then
      echo "$serial" >serial
    fi
    qrencode -t utf8 <"$user.conf"
  '';
  forwardFirewall = pkgs.writeShellScript "wg0-forward-firewall" ''
    set -euo pipefail

    {
      echo "flush set inet wg0-forward-firewall trusted_users"
      echo "flush set inet wg0-forward-firewall full_tunnel_users"
      echo "flush set inet wg0-forward-firewall allowed_destinations"

      for config in ${userDir}/*.conf; do
        user=''${config##*/}
        user=''${user%.conf}
        address=$(sed -n 's/^[[:space:]]*Address[[:space:]]*=[[:space:]]*//p' "$config")
        source=''${address%%/*}
        allowed=$(sed -n 's/^[[:space:]]*AllowedIPs[[:space:]]*=[[:space:]]*//p' "$config")
        allowed=''${allowed//[[:space:]]/}

        if [ "$allowed" = "0.0.0.0/0" ]; then
          case "$user" in
            yifan*) user_set=trusted_users ;;
            *) user_set=full_tunnel_users ;;
          esac
          printf 'add element inet wg0-forward-firewall %s { %s }\n' "$user_set" "$source"
        else
          destinations=''${allowed//,/, $source . }
          printf 'add element inet wg0-forward-firewall allowed_destinations { %s . %s }\n' "$source" "$destinations"
        fi
      done
    } | nft -f -
  '';
in {
  environment.etc."wireguard/new" = {
    source = newClient;
    mode = "0550";
  };

  environment.systemPackages = [
    pkgs.qrencode
    pkgs.wireguard-tools
  ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 root root -"
    "d ${userDir} 0700 root root -"
    "f ${userDir}/serial 0600 root root - 1"
  ];

  networking.wg-quick.interfaces.wg0.configFile = "${stateDir}/wg0.conf";

  networking.nftables.tables.wg0-forward-firewall = {
    family = "inet";
    content = ''
      set trusted_users {
        type ipv4_addr
      }

      set full_tunnel_users {
        type ipv4_addr
      }

      set allowed_destinations {
        type ipv4_addr . ipv4_addr
        flags interval
      }

      chain forward {
        type filter hook forward priority filter - 1; policy accept;
        ct state established,related accept
        iifname "wg0" ip saddr @trusted_users accept
        iifname "wg0" ip saddr @full_tunnel_users ip daddr != 100.0.0.0/10 accept
        iifname "wg0" ip saddr . ip daddr @allowed_destinations accept
        iifname "wg0" drop
      }
    '';
  };

  systemd.services.wg0-forward-firewall = {
    description = "WireGuard user forwarding firewall";
    wantedBy = ["multi-user.target"];
    after = ["nftables.service"];
    requires = ["nftables.service"];
    path = [pkgs.nftables];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = forwardFirewall;
      ExecReload = forwardFirewall;
    };
  };

  systemd.services.nftables.unitConfig.PropagatesReloadTo = ["wg0-forward-firewall.service"];
}
