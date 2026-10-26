{
  config,
  inputs,
  pkgs,
  ...
}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [
    inputs.codex-capacity-proxy.nixosModules.default
    ../../optional/acme-certificates.nix
    ../../optional/bitmagnet.nix
  ];

  services = {
    codex-capacity-proxy.enable = true;
    postgresql.dataDir = "/srv/docker/bitmagnet-postgres";
    acmeCertificates = {
      enable = true;
      restartServices = ["tailscale-serve"];
    };
    tailscale.serve = {
      enable = true;
      services = {
        bitmagnet.endpoints."tcp:80" = "http://${config.services.bitmagnet.settings.http_server.port}";
        codex-capacity-proxy = {
          certificate = {
            certFile = "${certDir}/fullchain.pem";
            keyFile = "${certDir}/privkey.pem";
          };
          tlsEndpoints."tcp:443" = "http://127.0.0.1:${toString config.services.codex-capacity-proxy.port}";
        };
      };
    };
  };

  systemd.services.btrfs-defrag-srv = {
    description = "Defragment and compress /srv";
    startAt = "weekly";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.btrfs-progs}/bin/btrfs filesystem defragment -r -czstd /srv";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.btrfs-defrag-srv.timerConfig.Persistent = true;
}
