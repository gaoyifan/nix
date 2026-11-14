{
  config,
  lib,
  nylonTopology,
  pkgs,
  ...
}: let
  host = config.networking.hostName;
  topology = nylonTopology.topology;
  peer = topology.peers.${host};
  exit =
    lib.findFirst
    (candidate: candidate.nodeId == "oracle2" && candidate.name == "public")
    (throw "home-router Google egress requires the Nylon exit oracle2/public")
    topology.catalog;
  # The Nylon selector installs IPv6 outlet routes only for IPv6-capable peers
  # and exits; otherwise the address-family classification rules keep rejecting.
  ipv6 =
    peer.selector.ipv6
    && exit.families.ipv6;
in {
  # Every home router in the Nylon mesh uses this same Google exit. Hosts outside
  # the mesh, such as the VM test harness, keep their default routing.
  config = lib.mkIf (lib.hasAttr host topology.peers) {
    # iif 0 limits these rules to locally generated traffic; forwarded traffic
    # keeps the normal outlet classification.
    networking.homeRouter.egress.classification.extraRules =
      [
        ''meta iif 0 ip daddr @google counter meta mark set ${exit.markHex} ct mark set meta mark return''
      ]
      ++ lib.optional ipv6 ''meta iif 0 ip6 daddr @google6 counter meta mark set ${exit.markHex} ct mark set meta mark return'';

    networking.nftables.tables.home-router.content = lib.concatStringsSep "\n" (
      [''include "${pkgs.nft-geo-sets}/set-google.conf"'']
      ++ lib.optional ipv6 ''include "${pkgs.nft-geo-sets}/set-google6.conf"''
    );
  };
}
