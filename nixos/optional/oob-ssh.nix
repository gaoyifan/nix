{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  cfg = config.services.oobSsh;
  namespace = "oob";
  interface = "oob0";
  parentDevice = "sys-subsystem-net-devices-${utils.escapeSystemdPath cfg.parentInterface}.device";
  rootAuthorizedKeys = config.users.users.root.openssh.authorizedKeys;
in {
  options.services.oobSsh = {
    enable = lib.mkEnableOption "SSH isolated from the host network namespace";

    parentInterface = lib.mkOption {
      type = lib.types.str;
      description = "Standalone Ethernet interface on which to create the OOB macvlan.";
      example = "eth0";
    };

    address = lib.mkOption {
      type = lib.types.str;
      description = "Static CIDR address assigned to the OOB macvlan.";
      example = "10.42.0.233/24";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."oob-ssh/authorized_keys" = {
      mode = "0444";
      text = ''
        ${lib.concatStringsSep "\n" rootAuthorizedKeys.keys}
        ${lib.concatMapStrings (file: lib.readFile file + "\n") rootAuthorizedKeys.keyFiles}
      '';
    };

    systemd.services = {
      oob-netns = {
        description = "OOB network namespace";
        requires = [parentDevice];
        after = [parentDevice];
        restartIfChanged = false;
        path = [pkgs.iproute2];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          parent=${lib.escapeShellArg "/sys/class/net/${cfg.parentInterface}"}
          read -r ifindex < "$parent/ifindex"
          read -r iflink < "$parent/iflink"
          test "$ifindex" = "$iflink"
          test ! -e "$parent/master"

          ip netns add ${namespace}
          trap 'ip netns delete ${namespace}' EXIT
          ip link add ${interface} link ${lib.escapeShellArg cfg.parentInterface} type macvlan mode bridge
          ip link set ${interface} netns ${namespace}
          ip netns exec ${namespace} ${lib.getExe' pkgs.procps "sysctl"} -qw net.ipv6.conf.${interface}.disable_ipv6=1
          ip -n ${namespace} address add ${lib.escapeShellArg cfg.address} dev ${interface}
          ip -n ${namespace} link set ${interface} up
          ip -n ${namespace} link set lo up
          trap - EXIT
        '';
        preStop = ''
          ip netns delete ${namespace}
        '';
      };

      oob-ssh = {
        description = "SSH isolated from the host network namespace";
        wantedBy = ["multi-user.target"];
        bindsTo = ["oob-netns.service"];
        after = ["oob-netns.service"];
        restartIfChanged = false;
        preStart = ''
          if ! test -s /var/lib/oob-ssh/host-key; then
            ${pkgs.dropbear}/bin/dropbearkey -t ed25519 -f /var/lib/oob-ssh/host-key
          fi
        '';
        serviceConfig = {
          Type = "exec";
          ExecStart = "${pkgs.dropbear}/bin/dropbear -F -E -s -j -k -D /etc/oob-ssh -r /var/lib/oob-ssh/host-key -p 22 -P /run/oob-ssh/dropbear.pid";
          NetworkNamespacePath = "/run/netns/${namespace}";
          Restart = "always";
          RestartSec = 7;
          RuntimeDirectory = "oob-ssh";
          StateDirectory = "oob-ssh";
          StateDirectoryMode = "0700";
        };
      };
    };
  };
}
