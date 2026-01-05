# WireGuard WAN configuration using systemd-networkd
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.router;
  wg = cfg.wgWan;
  secrets = config.services.secrets.nixos.${config.networking.hostName};
in
  lib.mkIf wg.enable {
    # WireGuard netdev
    systemd.network.netdevs."50-${wg.ifname}" = {
      netdevConfig = {
        Name = wg.ifname;
        Kind = "wireguard";
        MTUBytes = toString wg.mtu;
      };
      wireguardConfig = {
        PrivateKeyFile = secrets.wireguard.privateKeyFile;
        ListenPort = wg.listenPort;
        FirewallMark = wg.fwMark;
      };
      wireguardPeers = [
        {
          PublicKey = wg.peer.publicKey;
          Endpoint = wg.peer.endpoint;
          AllowedIPs = wg.peer.allowedIPs;
          PersistentKeepalive = wg.peer.persistentKeepalive;
        }
      ];
    };

    # WireGuard network configuration
    systemd.network.networks."50-${wg.ifname}" = {
      matchConfig.Name = wg.ifname;
      address = [wg.address];
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
      };
      linkConfig.RequiredForOnline = "no";
      routes = [
        {
          Destination = "0.0.0.0/0";
          Table = wg.routeTable;
        }
      ];
    };
  }
