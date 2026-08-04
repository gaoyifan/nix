{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
  derper = "${inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.tailscale.derper}/bin/derper";
  derps = {
    chinanet = {
      hostname = "el2-chinanet.gaof.net";
      listen = "202.141.162.72:10000";
    };
    cmcc = {
      hostname = "el2-cmcc.gaof.net";
      listen = "202.141.178.7:10001";
    };
    cernet = {
      hostname = "el2-cernet.gaof.net";
      listen = "202.38.93.98:10002";
    };
    ipv6 = {
      hostname = "el2-ipv6.gaof.net";
      listen = "[2001:da8:d800:931::98]:10003";
    };
  };
in {
  imports = [
    ../../optional/acme-certificates.nix
    ../../optional/diverge.nix
  ];

  services.openssh.settings.MaxStartups = 100;
  services.fail2ban.enable = true;
  services.diverge.enable = true;
  services.acmeCertificates = {
    enable = true;
    restartServices = map (name: "derp-${name}") (lib.attrNames derps) ++ ["podman-light-single"];
  };

  systemd.services = lib.mapAttrs' (name: derp: let
    runtimeDirectory = "derp-${name}";
    runtimeDir = "/run/${runtimeDirectory}";
  in
    lib.nameValuePair "derp-${name}" {
      description = "Tailscale DERP server for ${name}";
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
          "${lib.getExe' pkgs.coreutils "ln"} -sfn ${certDir}/fullchain.pem ${runtimeDir}/${derp.hostname}.crt"
          "${lib.getExe' pkgs.coreutils "ln"} -sfn ${certDir}/privkey.pem ${runtimeDir}/${derp.hostname}.key"
        ];
        ExecStart = "${derper} --hostname ${derp.hostname} --certdir ${runtimeDir} --certmode manual --verify-clients --http-port=-1 -a ${derp.listen}";
      };
    })
  derps;

  virtualisation.oci-containers.containers = {
    light-single = {
      image = "docker.io/gaoyifan/light-server:single";
      volumes = ["${certDir}:/usr/local/openresty/nginx/conf/ssl:ro"];
      extraOptions = ["--network=host"];
    };
  };

  services.resolved.settings.Resolve = {
    DNS = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    Domains = ["~."];
  };
  services.resolved.dnsDelegates = {
    cjia.Delegate = {
      DNS = ["100.65.1.254"];
      Domains = ["cjia.gaof.net"];
    };
    wgIplcEndpoint.Delegate = {
      DNS = [
        "223.5.5.5"
        "223.6.6.6"
      ];
      Domains = ["int.automesh.org"];
    };
  };
}
