{
  lib,
  pkgs,
  ...
}: {
  networking.edgeFirewall.publicTcpPorts = ["2221"];

  virtualisation.oci-containers.containers.mutagen-sync = {
    autoStart = false;
    image = "lscr.io/linuxserver/openssh-server:latest";
    environment = {
      PUID = "1000";
      PGID = "1000";
      USER_NAME = "syncd";
      PASSWORD_ACCESS = "false";
      SUDO_ACCESS = "false";
      LISTEN_PORT = "2221";
      TZ = "Asia/Shanghai";
    };
    volumes = [
      "/pool0/docker/mutagen-sync/config:/config"
      "/pool0/docker/mutagen-sync/data:/data"
    ];
    extraOptions = ["--network=host"];
  };

  systemd.services.podman-mutagen-sync = {
    wantedBy = ["el2-services.target"];
    requires = ["mount-el2-encrypted-datasets.service"];
    after = ["mount-el2-encrypted-datasets.service"];
    preStart = ''
      ${lib.getExe' pkgs.coreutils "install"} -d -m 0755 -o 1000 -g 1000 \
        /pool0/docker/mutagen-sync/config \
        /pool0/docker/mutagen-sync/data
    '';
  };
}
