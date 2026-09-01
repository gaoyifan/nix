{lib, ...}: {
  virtualisation.oci-containers.containers = {
    plex = {
      autoStart = false;
      image = "docker.io/plexinc/pms-docker:latest";
      environment = {
        TZ = "Asia/Shanghai";
        PLEX_UID = "1000";
        PLEX_GID = "100";
        CHANGE_CONFIG_DIR_OWNERSHIP = "false";
        ADVERTISE_IP = "http://el2.ts.gaof.net:32400";
      };
      volumes = [
        "/pool1/services/plex/config:/config"
        "/pool1/services/plex/transcode:/transcode"
        "/pool0/media0:/data:ro"
        "/pool0/media1:/data1:ro"
      ];
      extraOptions = ["--network=host"];
      podman.sdnotify = "healthy";
    };

    metatube = {
      autoStart = false;
      image = "ghcr.io/metatube-community/metatube-server:latest";
      ports = ["8080:8080"];
      volumes = ["/pool1/services/metatube:/cache"];
      cmd = [
        "-dsn"
        "/cache/metatube.db"
        "-port"
        "8080"
      ];
    };
  };

  systemd.services.podman-plex = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
    serviceConfig.TimeoutStartSec = lib.mkForce "2min";
  };
  systemd.services.podman-metatube = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };
}
