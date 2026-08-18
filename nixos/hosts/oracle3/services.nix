{
  config,
  lib,
  ...
}: let
  appEnvironmentFile = "/run/agenix/emotion-hrv-env";
  ghcrTokenFile = "/run/agenix/emotion-hrv-ghcr-token";
  postgresEnvironmentFile = "/run/agenix/emotion-hrv-postgres-env";
in {
  imports = [
    ../../optional/authoritative-ns.nix
    ../../optional/edge-firewall.nix
    ../../optional/nylon-public-exit.nix
  ];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    emotion-hrv-env.file = config.services.secrets.filesDir + "/nixos/oracle3/emotion-hrv-env.age";
    emotion-hrv-ghcr-token.file = config.services.secrets.filesDir + "/nixos/oracle3/emotion-hrv-ghcr-token.age";
    emotion-hrv-postgres-env.file = config.services.secrets.filesDir + "/nixos/oracle3/emotion-hrv-postgres-env.age";
  };

  virtualisation = {
    podman = {
      enable = true;
      defaultNetwork.settings = {
        dns_enabled = false;
        subnets = [
          {
            gateway = "10.88.0.1";
            subnet = "10.88.0.0/16";
          }
        ];
      };
    };
    oci-containers = {
      backend = "podman";
      containers = {
        emotion-hrv-postgres = {
          image = "postgres@sha256:57c72fd2a128e416c7fcc499958864df5301e940bca0a56f58fddf30ffc07777";
          pull = "missing";
          environment = {
            POSTGRES_USER = "postgres";
            POSTGRES_DB = "emotion_hrv";
          };
          environmentFiles = [postgresEnvironmentFile];
          volumes = ["/srv/docker/emotion-hrv/postgres:/var/lib/postgresql/data"];
          extraOptions = [
            "--health-cmd=pg_isready -U postgres -d emotion_hrv"
            "--health-interval=5s"
            "--health-timeout=5s"
            "--health-retries=12"
            "--ip=10.88.0.2"
          ];
          podman.sdnotify = "healthy";
        };
        emotion-hrv-app = {
          image = "ghcr.io/neighbork/emotion-hrv@sha256:27a2e729b223fd088e45640c7a3c3b0870cd9ebea796bd107591cadb396e55c1";
          pull = "missing";
          login = {
            registry = "ghcr.io";
            username = "gaoyifan";
            passwordFile = ghcrTokenFile;
          };
          dependsOn = ["emotion-hrv-postgres"];
          environment = {
            APP_HOST = "0.0.0.0";
            APP_PORT = "8080";
            MPLBACKEND = "Agg";
          };
          environmentFiles = [appEnvironmentFile];
          ports = ["80:8080"];
          volumes = ["/srv/docker/emotion-hrv/logs:/app/logs"];
          extraOptions = [
            "--add-host=host.docker.internal:host-gateway"
            "--add-host=postgres:10.88.0.2"
            "--health-cmd=none"
          ];
        };
      };
    };
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraSetFlags = [
      "--accept-dns=false"
      "--accept-routes"
      "--advertise-exit-node=false"
      "--netfilter-mode=off"
      "--operator=yifan"
      "--snat-subnet-routes=false"
    ];
  };

  networking.edgeFirewall = {
    enable = true;
    extraTrustedInterfaces = ["podman0"];
    extraPublicTcpPorts = [
      "53"
      "80"
    ];
    extraPublicUdpPorts = [
      "53"
    ];
    extraForwardRules = [
      ''iifname "ens3" oifname "podman0" ct status dnat accept''
    ];
  };

  systemd = {
    services.podman-emotion-hrv-app.unitConfig.ConditionPathExists = "/srv/docker/emotion-hrv/.restored";
    tmpfiles.rules = [
      "d /srv/docker/emotion-hrv 0700 root root -"
      "d /srv/docker/emotion-hrv/logs 0755 root root -"
      "d /srv/docker/emotion-hrv/postgres 0700 root root -"
    ];
  };
}
