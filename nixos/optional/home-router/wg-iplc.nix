{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter.wgIplc;
  peer = import (config.services.secrets.filesDir + "/nixos/wg-iplc.nix");
in {
  options.networking.homeRouter.wgIplc = {
    enable = lib.mkEnableOption "the shared wgIplc outlet";
    ip = lib.mkOption {
      type = lib.types.str;
      description = "Address assigned to wg-iplc.";
    };
    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Age-encrypted WireGuard private key.";
    };
    mark = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "0x100";
      description = "Packet mark selecting wgIplc.";
    };
    table = lib.mkOption {
      type = lib.types.int;
      readOnly = true;
      default = 5100;
      description = "Routing table selected by the wgIplc packet mark.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.wg-iplc-private-key = lib.mkIf config.services.secrets.hasRealFiles {
      file = cfg.privateKeyFile;
    };
    networking.homeRouter.wlt.defaultOutlet.ipv4Mark = lib.mkDefault cfg.mark;
    networking.wireguard.interfaces.wg-iplc = {
      ips = [cfg.ip];
      privateKeyFile = "/run/agenix/wg-iplc-private-key";
      mtu = 1392;
      table = toString cfg.table;
      fwMark = "0x90000";
      peers = [
        {
          inherit (peer) publicKey endpoint;
          allowedIPs = ["0.0.0.0/0"];
          persistentKeepalive = 60;
        }
      ];
    };
    networking.policyRouting.ipv4.routingPolicyRules.wltOutlet = [
      "fwmark ${cfg.mark}/0xfff lookup ${toString cfg.table}"
    ];
  };
}
