{
  config,
  lib,
  pkgs,
  ...
}: let
  homeRouter = config.networking.homeRouter;
  port = "1080";
in {
  options.networking.homeRouter.ttr.enable = lib.mkEnableOption "transparent splitting of public IPv4 TCP connections from non-guest LANs";

  config = lib.mkIf (homeRouter.enable && homeRouter.ttr.enable) {
    # Let TTR inherit the classified SYN's mark and copy it to its outbound socket.
    boot.kernel.sysctl."net.ipv4.tcp_fwmark_accept" = 1;

    networking.nftables.tables.home-router.content = ''
      chain tcp-repeater-prerouting {
        type nat hook prerouting priority dstnat + 1; policy accept;
        iifname != { ${lib.concatMapStringsSep ", " (interface: ''"${interface}"'') homeRouter.internalInterfaces} } return
        fib daddr type local return
        ip daddr @private_v4 return
        ip daddr { 0.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 198.18.0.0/15, 224.0.0.0/3 } return
        ip protocol tcp redirect to :${port}
      }
    '';

    systemd.services.tcp-transparent-repeater = {
      description = "Transparent TCP splitting for LAN internet traffic";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.tcp-transparent-repeater} 0.0.0.0:${port}";
        DynamicUser = true;
        AmbientCapabilities = ["CAP_NET_ADMIN"];
        CapabilityBoundingSet = ["CAP_NET_ADMIN"];
        Restart = "always";
      };
    };
  };
}
