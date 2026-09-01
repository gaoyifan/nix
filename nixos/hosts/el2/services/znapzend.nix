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

  systemd.services.znapzend = {
    after = ["zfs-import-pool1.service"];
    requires = ["zfs-import-pool1.service"];
    preStart = lib.mkBefore ''
      zfs set org.znapzend:enabled=off pool0/backup pool0/footage
    '';
  };
}
