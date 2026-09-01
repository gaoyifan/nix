{
  el2WanAddresses,
  lib,
  ...
}: {
  imports = [../../../optional/bitmagnet.nix];

  networking.edgeFirewall.extraPublicUdpPorts = ["3334"];

  services.bitmagnet.settings.dht_server.local_address = el2WanAddresses.chinanet.ipv4;
  services.postgresql.dataDir = "/pool1/services/bitmagnet-postgres";

  systemd.targets.postgresql.wantedBy = lib.mkForce ["el2-services.target"];
  systemd.services.postgresql = {
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };
  systemd.services.bitmagnet.wantedBy = lib.mkForce ["el2-services.target"];
}
