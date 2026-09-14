{lib, ...}: {
  imports = [../../../optional/znapzend-mail.nix];

  services.znapzend = {
    enable = true;
    logLevel = "warning";
    features = {
      sendRaw = true;
      zfsGetType = true;
    };
    zetup.services = {
      dataset = "pool1/services";
      plan = "1d=>1h,2w=>1d,8w=>1w,1y=>1m";
      destinations."0" = {
        host = "root@nfs.s.gaof.net";
        dataset = "pool0/el2/services";
        plan = "1d=>1h,2w=>1d,8w=>1w,1y=>1m";
      };
    };
    zetup.kingdee = {
      dataset = "pool1/incus/virtual-machines/kingdee.block";
      plan = "1hours=>10minutes,1days=>8hours,30days=>7days";
      destinations."0" = {
        host = "root@nfs.s.gaof.net";
        dataset = "pool0/pve-backup/vm-200-disk-0";
        plan = "1hours=>10minutes,1days=>8hours,30days=>7days";
      };
    };
  };

  services.resolved.dnsDelegates.znapzendNfs.Delegate = {
    DNS = [
      "223.5.5.5"
      "119.29.29.29"
    ];
    Domains = ["nfs.s.gaof.net"];
  };

  systemd.services.znapzend = {
    wantedBy = lib.mkForce ["el2-services.target"];
    after = [
      "zfs-import-pool1.service"
      "zfs-unlock-mount.service"
    ];
    requires = [
      "zfs-import-pool1.service"
      "zfs-unlock-mount.service"
    ];
    preStart = lib.mkBefore ''
      zfs set org.znapzend:enabled=off pool0/backup pool0/footage
    '';
  };
}
