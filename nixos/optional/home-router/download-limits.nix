{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  cfg = config.networking.homeRouter;
  clientsByInterface = lib.concatMapAttrs (_: lan:
    lib.optionalAttrs (lan.downloadLimitsMbps != {}) {
      ${lan.interface} = lib.imap1 (index: address: {
        inherit address;
        class = "1:${lib.toHexString index}";
        rate = toString lan.downloadLimitsMbps.${address};
      }) (lib.attrNames lan.downloadLimitsMbps);
    })
  cfg.lans;
in {
  config = lib.mkIf (cfg.enable && clientsByInterface != {}) {
    # After reverse NAT both forwarded and transparent-proxy replies have the public source IP.
    networking.nftables.tables.home-router.content = lib.mkAfter ''
      chain download-limits {
        type filter hook postrouting priority srcnat + 1; policy accept;
        ${lib.concatMapAttrsStringSep "\n" (iface:
        lib.concatMapStringsSep "\n" (client: ''
          oifname "${iface}" ip daddr ${client.address} ip saddr != @private_v4 counter meta priority set ${client.class}
        ''))
      clientsByInterface}
      }
    '';

    # networkd cannot reapply an existing HTB qdisc on reload.
    systemd.services = lib.mapAttrs' (iface: clients: let
      device = "sys-subsystem-net-devices-${utils.escapeSystemdPath iface}.device";
    in
      lib.nameValuePair "download-limits-${iface}" {
        description = "Limit internet downloads on ${iface}";
        wantedBy = ["multi-user.target" device];
        bindsTo = [device];
        after = [device];
        path = [pkgs.iproute2];
        script = ''
          tc qdisc add dev ${iface} root handle 1: htb
          ${lib.concatMapStringsSep "\n" (client: ''
              tc class add dev ${iface} parent 1: classid ${client.class} htb rate ${client.rate}mbit
              tc qdisc add dev ${iface} parent ${client.class} fq_codel
            '')
            clients}
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStopPost = "-${lib.getExe' pkgs.iproute2 "tc"} qdisc del dev ${iface} root handle 1:";
        };
      })
    clientsByInterface;
  };
}
