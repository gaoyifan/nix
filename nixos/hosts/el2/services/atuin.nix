{lib, ...}: let
  dataDirectory = "/pool1/services/atuin";
in {
  users = {
    groups.atuin = {};
    users.atuin = {
      isSystemUser = true;
      group = "atuin";
    };
  };

  services = {
    atuin = {
      enable = true;
      openRegistration = true;
      database = {
        createLocally = false;
        uri = "sqlite://${dataDirectory}/atuin.db";
      };
    };
    tailscale.serve.services.atuin-server.endpoints."tcp:80" = "http://127.0.0.1:8888";
  };

  systemd.services.atuin = {
    wantedBy = lib.mkForce ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
    unitConfig.ConditionPathExists = "${dataDirectory}/atuin.db";
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "atuin";
      Group = "atuin";
    };
  };
}
