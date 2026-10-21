{
  config,
  inputs,
  lib,
  ...
}: let
  certDirectory = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [inputs.findmy-history.nixosModules.default];

  services.findmy = {
    enable = true;
    sourceUrl = "http://100.64.2.80:8766/events";
    tokenFile = "/pool1/services/findmy/source.token";
    dataDir = "/pool1/services/findmy";
  };

  systemd.services.findmy = {
    wantedBy = lib.mkForce ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
  };

  services.tailscale.serve.services.findmy = {
    certificate = {
      certFile = "${certDirectory}/fullchain.pem";
      keyFile = "${certDirectory}/privkey.pem";
    };
    tlsEndpoints."tcp:443" = "http://127.0.0.1:8787";
  };
}
