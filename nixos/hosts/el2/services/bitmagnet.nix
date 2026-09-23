{
  config,
  el2WanAddresses,
  lib,
  ...
}: let
  dhtPort = toString config.services.bitmagnet.settings.dht_server.port;
in {
  imports = [../../../optional/bitmagnet.nix];

  # Keep the service identity stable for the conntrack event rule.
  users.users.bitmagnet.uid = 992;

  networking.edgeFirewall.extraPublicUdpPorts = [dhtPort];
  networking.nftables.tables.bitmagnet-conntrack-events = {
    family = "inet";
    content = ''
      chain output {
        type filter hook output priority -150; policy accept;
        meta skuid ${toString config.users.users.bitmagnet.uid} counter ct event set 0
      }

      chain input {
        type filter hook input priority -150; policy accept;
        ip daddr ${el2WanAddresses.chinanet.ipv4} udp dport ${dhtPort} counter ct event set 0
      }
    '';
  };

  services.bitmagnet.settings.dht_server.local_address = el2WanAddresses.chinanet.ipv4;
  services.postgresql.dataDir = "/pool1/services/bitmagnet-postgres";

  systemd.targets.postgresql.wantedBy = lib.mkForce ["el2-services.target"];
  systemd.services.postgresql = {
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };
  systemd.services.bitmagnet.wantedBy = lib.mkForce ["el2-services.target"];
}
