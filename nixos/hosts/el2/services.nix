{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
  tailscale = inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.tailscale;
  derper = "${tailscale.derper}/bin/derper";
  stund = tailscale.overrideAttrs {
    pname = "stund";
    outputs = ["out"];
    subPackages = ["cmd/stund"];
    postInstall = "";
  };
  stunListenAddresses = {
    chinanet = "202.141.162.72:3478";
    cmcc = "202.141.178.7:3478";
    cernet = "202.38.93.98:3478";
    ipv6 = "[2001:da8:d800:931::98]:3478";
  };
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    acme-repository-pull-key.file = config.services.secrets.filesDir + "/nixos/acme-repository-pull-key.age";
  };

  imports = [
    ../../optional/acme-certificates.nix
    ../../optional/diverge.nix
  ];

  services.openssh.settings.MaxStartups = 100;
  services.fail2ban.enable = true;
  services.diverge.enable = true;
  services.ncps = {
    enable = true;
    analytics.reporting.enable = false;
    cache = {
      hostName = "ncps";
      storage.local = "/pool1/nix-cache";
      maxSize = "45G";
      lru.schedule = "0 11 * * *";
      signNarinfo = false;
      upstream = {
        urls = ["https://cache.nixos.org"];
        publicKeys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        ];
      };
    };
  };
  services.acmeCertificates = {
    enable = true;
    restartServices = [
      "derp"
      "podman-light-single"
    ];
  };

  systemd.services =
    {
      derp = let
        runtimeDirectory = "derp";
        runtimeDir = "/run/${runtimeDirectory}";
        hostname = "el2.gaof.net";
      in {
        description = "Tailscale DERP server";
        wantedBy = ["multi-user.target"];
        wants = [
          "network-online.target"
          "tailscaled.service"
        ];
        after = [
          "network-online.target"
          "tailscaled.service"
        ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
          RuntimeDirectory = runtimeDirectory;
          ExecStartPre = [
            "${lib.getExe' pkgs.coreutils "ln"} -sfn ${certDir}/fullchain.pem ${runtimeDir}/${hostname}.crt"
            "${lib.getExe' pkgs.coreutils "ln"} -sfn ${certDir}/privkey.pem ${runtimeDir}/${hostname}.key"
          ];
          ExecStart = "${derper} --hostname ${hostname} --certdir ${runtimeDir} --certmode manual --verify-clients --http-port=-1 --stun=false -a :10000";
        };
      };
    }
    // lib.mapAttrs' (name: listenAddress:
      lib.nameValuePair "stun-${name}" {
        description = "Tailscale STUN server for ${name}";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
          ExecStart = "${stund}/bin/stund --stun ${listenAddress} --http 127.0.0.1:0";
        };
      })
    stunListenAddresses;

  virtualisation.oci-containers.containers = {
    light-single = {
      image = "docker.io/gaoyifan/light-server:single";
      volumes = ["${certDir}:/usr/local/openresty/nginx/conf/ssl:ro"];
      extraOptions = ["--network=host"];
    };
  };

  services.resolved.settings.Resolve = {
    DNS = [config.networking.homeRouter.serviceAddresses.ipv4];
    Domains = ["~."];
  };
  services.resolved.dnsDelegates.wgIplcEndpoint.Delegate = {
    DNS = [
      "223.5.5.5"
      "223.6.6.6"
    ];
    Domains = ["int.automesh.org"];
  };
}
