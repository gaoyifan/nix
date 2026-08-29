# Shared edge datapath for the el and el2 routers.
{
  config,
  lib,
  ...
}: let
  cfg = config.networking.elRouter;
  homeRouter = config.networking.homeRouter;

  ipv4Addresses = addresses: lib.filter (address: !(lib.hasInfix ":" address)) addresses;
  ipv6Addresses = addresses: lib.filter (address: lib.hasInfix ":" address) addresses;

  cernet = homeRouter.wans.cernet;
  chinanet = homeRouter.wans.chinanet;
  cmcc = homeRouter.wans.cmcc;
  cernetMark = cernet.routingTable;
  chinanetMark = chinanet.routingTable;
  cmccMark = cmcc.routingTable;
  formatMark = mark: "0x${lib.toLower (lib.toHexString mark)}";
in {
  options.networking.elRouter = {
    enable = lib.mkEnableOption "shared GNet multi-WAN edge datapath";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (name: lib.hasAttr name homeRouter.wans) [
          "cernet"
          "chinanet"
          "cmcc"
        ];
        message = "networking.elRouter requires cernet, chinanet, and cmcc homeRouter WANs.";
      }
      {
        assertion = ipv4Addresses cernet.addresses != [] && ipv6Addresses cernet.addresses != [];
        message = "networking.elRouter requires CERNET IPv4 and IPv6 addresses.";
      }
      {
        assertion = ipv4Addresses chinanet.addresses != [] && ipv4Addresses cmcc.addresses != [];
        message = "networking.elRouter requires China Telecom and China Mobile IPv4 addresses.";
      }
      {
        assertion = lib.all (wan: wan.routingTable != null) [
          cernet
          chinanet
          cmcc
        ];
        message = "networking.elRouter requires dedicated routing tables for all WANs.";
      }
    ];

    networking.homeRouter.wgIplc.enable = true;
    networking.wireguard.interfaces.wg-iplc.fwMark = lib.mkForce (toString chinanetMark);

    networking.homeRouter.egress.classification = {
      extraIngressInterfaces = ["tailscale0"];
      destinationAddressSetRules = [
        {
          set = "cernet";
          mark = formatMark cernetMark;
        }
        {
          set = "chinanet";
          mark = formatMark chinanetMark;
        }
        {
          set = "cmcc";
          mark = formatMark cmccMark;
        }
        {
          set = "cn";
          mark = formatMark chinanetMark;
        }
        {
          set = "cn6";
          mark = formatMark cernetMark;
        }
      ];
      extraRules = [
        ''udp sport 2197 return''
      ];
    };
  };
}
