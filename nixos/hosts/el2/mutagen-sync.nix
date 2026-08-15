{
  lib,
  pkgs,
  ...
}: let
  inherit (import ../../common/ssh-keys.nix) sshKeys;
in {
  networking.edgeFirewall.publicTcpPorts = ["2221"];

  containers.mutagen-sync = {
    ephemeral = true;
    bindMounts = {
      "/etc/ssh/ssh_host_ed25519_key".hostPath = "/pool1/services/mutagen-sync/ssh/ssh_host_ed25519_key";
      "/etc/ssh/ssh_host_rsa_key".hostPath = "/pool1/services/mutagen-sync/ssh/ssh_host_rsa_key";
      "/home/syncd" = {
        hostPath = "/pool1/services/mutagen-sync/config";
        isReadOnly = false;
      };
      "/data" = {
        hostPath = "/pool1/services/mutagen-sync/data";
        isReadOnly = false;
      };
    };
    config = {pkgs, ...}: {
      networking.firewall.enable = false;

      users = {
        groups.syncd.gid = 1000;
        users.syncd = {
          isNormalUser = true;
          uid = 1000;
          group = "syncd";
          openssh.authorizedKeys.keys = sshKeys;
        };
      };

      services.openssh = {
        enable = true;
        ports = [2221];
        settings = {
          AllowTcpForwarding = false;
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;
        };
      };

      environment.systemPackages = [pkgs.rsync];
      system.stateVersion = "26.05";
    };
  };

  systemd.services."container@mutagen-sync" = {
    wantedBy = ["el2-services.target"];
    requires = ["mount-el2-encrypted-datasets.service"];
    after = ["mount-el2-encrypted-datasets.service"];
    preStart = ''
      ${lib.getExe' pkgs.coreutils "install"} -d -m 0700 -o 1000 -g 1000 /pool1/services/mutagen-sync/config
      ${lib.getExe' pkgs.coreutils "install"} -d -m 0755 -o 1000 -g 1000 /pool1/services/mutagen-sync/data
    '';
  };
}
