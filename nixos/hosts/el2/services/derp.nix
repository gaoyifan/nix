{
  config,
  el2WanAddresses,
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
    chinanet = "${el2WanAddresses.chinanet.ipv4}:3478";
    cmcc = "${el2WanAddresses.cmcc.ipv4}:3478";
    cernet = "${el2WanAddresses.cernet.ipv4}:3478";
    ipv6 = "[${el2WanAddresses.cernet.ipv6}]:3478";
  };
in {
  networking.edgeFirewall = {
    extraPublicTcpPorts = ["10000"];
    extraPublicUdpPorts = ["3478"];
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
}
