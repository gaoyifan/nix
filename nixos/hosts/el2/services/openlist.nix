{
  virtualisation.oci-containers.containers.openlist = {
    autoStart = false;
    image = "ghcr.io/openlistteam/openlist-git:v4.1.8";
    user = "1000:1000";
    environment = {
      UMASK = "022";
      RUN_ARIA2 = "false";
    };
    volumes = [
      "/pool1/services/openlist:/opt/openlist/data"
      "/pool0:/mnt/pool0-ro:ro"
      "/pool0/media0:/mnt/pool0/media0"
      "/pool0/media1:/mnt/pool0/media1"
    ];
    extraOptions = ["--network=host"];
  };

  systemd.services.podman-openlist = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };
}
