{lib, ...}: let
  encryptedDatasets = [
    "pool0/backup"
    "pool0/docker_volume_maplebot_postgresql"
    "pool0/footage"
    "pool0/kopia"
    "pool0/syncthing"
  ];
in {
  imports = [
    ../../optional/zfs-unlock.nix
    ../../optional/znapzend-mail.nix
  ];

  services = {
    smartd.enable = true;
    zfs.autoScrub.enable = true;
    znapzend = {
      enable = true;
      pure = true;
      logLevel = "warning";
      features = {
        sendRaw = true;
        zfsGetType = true;
      };
      zetup = {
        backup = {
          dataset = "pool0/backup";
          plan = "1h=>10min,30d=>1d,90d=>1w";
          destinations."0" = {
            host = "root@202.38.93.98";
            dataset = "pool0/backup";
            plan = "1h=>10min,30d=>1d,1y=>1w";
          };
        };
        footage = {
          dataset = "pool0/footage";
          plan = "30d=>1d,90d=>1w";
          destinations."0" = {
            host = "root@202.38.93.98";
            dataset = "pool0/footage";
            plan = "30d=>1d,1y=>1w";
          };
        };
      };
    };
  };

  programs.zfsUnlock.datasets = encryptedDatasets;

  systemd.services.znapzend = {
    after = ["network-online.target"];
    wants = ["network-online.target"];
    preStart = lib.mkAfter ''
      zfs set org.znapzend:dst_0_mbuffer=/run/current-system/sw/bin/mbuffer pool0/backup
      zfs set org.znapzend:dst_0_mbuffer=/run/current-system/sw/bin/mbuffer pool0/footage
    '';
  };
}
