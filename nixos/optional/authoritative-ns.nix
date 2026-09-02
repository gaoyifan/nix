{
  config,
  lib,
  pkgs,
  ...
}: let
  lightningstreamConfig = (pkgs.formats.yaml {}).generate "lightningstream.yaml" {
    instance = config.networking.hostName;
    storage_poll_interval = "8s";
    lmdbs = {
      main = {
        path = "/var/lib/powerdns/pdns.lmdb";
        schema_tracks_changes = true;
        options = {
          no_subdir = true;
          create = true;
        };
      };
      shard = {
        path = "/var/lib/powerdns/pdns.lmdb-0";
        schema_tracks_changes = true;
        options = {
          no_subdir = true;
          create = true;
        };
      };
    };
    sweeper = {
      enabled = true;
      retention_days = 30;
      first_interval = "1m";
    };
    storage = {
      type = "s3";
      options = {
        access_key = "\${S3_ACCESS_KEY}";
        secret_key = "\${S3_SECRET_KEY}";
        region = "\${S3_REGION}";
        bucket = "\${S3_BUCKET}";
        endpoint_url = "\${S3_ENDPOINT}";
        use_update_marker = true;
      };
      cleanup = {
        enabled = true;
        interval = "24h";
      };
    };
  };
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    lightningstream-env = {
      file = config.services.secrets.filesDir + "/nixos/lightningstream-env.age";
      owner = "pdns";
      group = "pdns";
    };
  };

  services = {
    powerdns = {
      enable = true;
      extraConfig = ''
        launch=lmdb
        lmdb-filename=/var/lib/powerdns/pdns.lmdb
        lmdb-shards=1
        lmdb-lightning-stream=yes
        views=yes
        edns-subnet-processing=yes
        zone-cache-refresh-interval=1
        zone-metadata-cache-ttl=0
        dname-processing=yes
        expand-alias=yes
        resolver=[::1]:53
        security-poll-suffix=
        enable-lua-records=yes
      '';
    };
    resolved = {
      enable = true;
      settings.Resolve.DNSStubListener = false;
    };
  };

  environment.etc = {
    "lightningstream.yaml".source = lightningstreamConfig;
    "resolv.conf".source = lib.mkForce "/run/systemd/resolve/resolv.conf";
  };

  systemd.services = {
    pdns.serviceConfig.StateDirectory = "powerdns";
    lightningstream = {
      description = "Synchronize PowerDNS LMDB databases through S3";
      wantedBy = ["multi-user.target"];
      requires = ["pdns.service"];
      after = ["pdns.service"];
      serviceConfig = {
        User = "pdns";
        Group = "pdns";
        EnvironmentFile = "/run/agenix/lightningstream-env";
        ExecStart = "${lib.getExe pkgs.lightningstream} --config /etc/lightningstream.yaml sync";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };
  };
}
