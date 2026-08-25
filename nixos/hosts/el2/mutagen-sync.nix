{
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (import ../../common/ssh-keys.nix) sshKeys;
  fanotifyAgent = pkgs.mutagen-fanotify-agent;
  agentState = "/var/lib/mutagen-sync/.mutagen";
  agentDirectory = "${agentState}/agents/${fanotifyAgent.version}";
  volumeDirectory = "/pool1/services/mutagen-sync/volumes";
in {
  imports = [inputs.microvm.nixosModules.host];

  networking.edgeFirewall.extraPublicTcpPorts = ["2221"];

  microvm.vms.mutagen-sync = {
    autostart = false;
    config = {
      config,
      lib,
      ...
    }: {
      users = {
        groups.syncd.gid = 1000;
        users.syncd = {
          group = "syncd";
          isNormalUser = true;
          openssh.authorizedKeys.keys = sshKeys;
          uid = 1000;
        };
      };

      services.openssh = {
        authorizedKeysFiles = lib.mkAfter ["/var/lib/mutagen-sync/ssh/authorized_keys"];
        enable = true;
        hostKeys = [
          {
            path = "/var/lib/mutagen-sync/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
        settings = {
          AllowTcpForwarding = false;
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;
          SetEnv = "MUTAGEN_SIDECAR=1";
        };
      };

      security.wrappers.mutagen-fanotify-agent = {
        source = lib.getExe fanotifyAgent;
        owner = "root";
        group = "syncd";
        permissions = "u+rx,g+rx,o-rwx";
        capabilities = "cap_sys_admin,cap_dac_read_search+ep";
      };

      systemd.tmpfiles.settings."10-mutagen-fanotify" = {
        "/var/lib/mutagen-sync/ssh".d = {
          mode = "0711";
          user = "root";
          group = "root";
        };
        "${agentState}".d = {
          mode = "0700";
          user = "syncd";
          group = "syncd";
        };
        "${agentState}/agents".d = {
          mode = "0700";
          user = "syncd";
          group = "syncd";
        };
        "${agentDirectory}".d = {
          mode = "0700";
          user = "syncd";
          group = "syncd";
        };
        "${agentDirectory}/mutagen-agent"."L+".argument = "${config.security.wrapperDir}/mutagen-fanotify-agent";
        "/data".d = {
          mode = "0755";
          user = "syncd";
          group = "syncd";
        };
        "/home/syncd/.mutagen"."L+".argument = agentState;
      };

      microvm = {
        forwardPorts = [
          {
            guest.port = 22;
            host = {
              address = "0.0.0.0";
              port = 2221;
            };
          }
        ];
        interfaces = [
          {
            id = "qemu";
            mac = "02:00:00:00:22:21";
            type = "user";
          }
        ];
        mem = 4096;
        shares = [
          {
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
            source = "/nix/store";
            tag = "ro-store";
          }
        ];
        vcpu = 4;
        volumes = [
          {
            image = "${volumeDirectory}/mutagen-state.img";
            label = "mutagen-state";
            mountPoint = "/var/lib/mutagen-sync";
            size = 512;
          }
          {
            image = "${volumeDirectory}/mutagen-data.img";
            label = "mutagen-data";
            mountPoint = "/data";
            size = 8192;
          }
        ];
      };

      system.stateVersion = "26.05";
    };
  };

  systemd.services."microvm@mutagen-sync" = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service"];
    serviceConfig.ExecStartPre = "+${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o microvm -g kvm ${volumeDirectory}";
  };
}
