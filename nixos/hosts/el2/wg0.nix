{pkgs, ...}: let
  stateDir = "/var/lib/wireguard";
  configFile = "${stateDir}/wg0.conf";
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
    echo "$serial" >"$user.serial"
    if [ "''${update_serial:-}" = 1 ]; then
      echo "$serial" >serial
    fi
    qrencode -t utf8 <"$user.conf"
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
    "d ${stateDir}/user 0700 root root -"
    "f ${stateDir}/user/serial 0600 root root - 1"
  ];

  networking.wg-quick.interfaces.wg0.configFile = configFile;
}
