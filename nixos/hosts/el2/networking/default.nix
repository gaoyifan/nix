{
  config,
  lib,
  ...
}: let
  addressFromCidr = cidr: lib.head (lib.splitString "/" cidr);
  wans = config.networking.homeRouter.wans;
in {
  imports = [
    ./firewall.nix
    ./home-router.nix
    ./tailscale.nix
    ./wg0.nix
    ./xu2hao.nix
  ];

  _module.args.el2WanAddresses = {
    cernet = {
      ipv4 = addressFromCidr (lib.head wans.cernet.addresses);
      ipv6 = addressFromCidr (lib.last wans.cernet.addresses);
    };
    chinanet.ipv4 = addressFromCidr (lib.head wans.chinanet.addresses);
    cmcc.ipv4 = addressFromCidr (lib.head wans.cmcc.addresses);
  };
}
