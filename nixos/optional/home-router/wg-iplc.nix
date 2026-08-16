{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter.wgIplc;
in {
  options.networking.homeRouter.wgIplc = {
    enable = lib.mkEnableOption "the shared wgIplc outlet";
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
    networking.homeRouter.wlt.defaultOutlet.ipv4Mark = lib.mkDefault cfg.mark;
    networking.wireguard.interfaces.wg-iplc = {
      table = toString cfg.table;
      fwMark = "0x90000";
    };
    networking.policyRouting.ipv4.routingPolicyRules.wltOutlet = [
      "fwmark ${cfg.mark}/0xfff lookup ${toString cfg.table}"
    ];
  };
}
