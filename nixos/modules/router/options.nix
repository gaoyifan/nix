# Router options definitions
{lib, ...}: let
  inherit (lib) mkOption mkEnableOption types;
in {
  options.router = {
    # LAN Configuration
    lan = {
      ifname = mkOption {
        type = types.str;
        example = "enp26s0";
        description = "LAN interface name";
      };
      address = mkOption {
        type = types.str;
        example = "192.168.10.1";
        description = "LAN IP address";
      };
      prefixLength = mkOption {
        type = types.int;
        default = 24;
        description = "LAN network prefix length";
      };
      dhcpRange = {
        start = mkOption {type = types.str;};
        end = mkOption {type = types.str;};
      };
      domain = mkOption {
        type = types.str;
        default = "lan";
      };
    };

    # WAN Configuration
    wan = {
      ifname = mkOption {
        type = types.str;
        example = "enp2s0";
        description = "WAN interface name (for PPPoE)";
      };
      managementAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "100.65.1.104/24";
        description = "Static management IP on WAN (optional)";
      };
      managementGateway = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "100.65.1.254";
        description = "Gateway for management network (optional)";
      };
    };

    # PPPoE Configuration
    pppoe = {
      enable = mkEnableOption "PPPoE WAN connection";
      peerName = mkOption {
        type = types.str;
        default = "isp";
      };
      ifname = mkOption {
        type = types.str;
        default = "ppp0";
      };
      user = mkOption {
        type = types.str;
        description = "PPPoE username";
      };
    };

    # WireGuard WAN Configuration
    wgWan = {
      enable = mkEnableOption "WireGuard as secondary WAN";
      ifname = mkOption {
        type = types.str;
        default = "wg-wan";
      };
      address = mkOption {
        type = types.str;
        example = "10.200.0.2/24";
      };
      listenPort = mkOption {
        type = types.int;
        default = 51820;
      };
      routeTable = mkOption {
        type = types.int;
        default = 200;
      };
      fwMark = mkOption {
        type = types.int;
        default = 51820;
      };
      mtu = mkOption {
        type = types.int;
        default = 1420;
      };
      peer = {
        publicKey = mkOption {type = types.str;};
        endpoint = mkOption {type = types.str;};
        allowedIPs = mkOption {
          type = types.listOf types.str;
          default = ["0.0.0.0/0"];
        };
        persistentKeepalive = mkOption {
          type = types.int;
          default = 25;
        };
      };
    };

    # Tailscale Configuration
    tailscale = {
      enable = mkEnableOption "Tailscale as secondary LAN";
      advertiseRoutes = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };

    # Policy Routing Configuration
    policyRouting = {
      wgMark = mkOption {
        type = types.int;
        default = 2;
      };
      wgDestinations = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["10.0.0.0/8" "172.16.0.0/12"];
        description = "Destinations to route through WireGuard";
      };
    };

    # AdGuard Home Configuration
    adguard = {
      enable = mkEnableOption "AdGuard Home for DNS/DHCP";
      webPort = mkOption {
        type = types.int;
        default = 3000;
      };
      upstreamDns = mkOption {
        type = types.listOf types.str;
        default = ["1.1.1.1" "8.8.8.8"];
      };
      bootstrapDns = mkOption {
        type = types.listOf types.str;
        default = ["1.1.1.1" "8.8.8.8"];
      };
    };
  };
}
