# Declarative Incus VM inventory shared by VM and network configuration.
let
  sshKey = (import ../../common/ssh-keys.nix).userKeys."yifan-macbook";

  # Applied by cloud-init on first boot only; rebuild the VM to change
  # (incus delete <name> --force, then re-run incus-apply-declarative-vms).
  # SSH is key-only for both users.
  userData = ''
    #cloud-config
    users:
      - name: root
        lock_passwd: false
        hashed_passwd: "*"
        ssh_authorized_keys:
          - ${sshKey}
      - name: agent
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        # cloud-init locks the password with "!", which new OpenSSH
        # rejects outright ("account is locked"), breaking pubkey auth.
        # "*" means no password but the account stays enabled.
        lock_passwd: false
        hashed_passwd: "*"
        ssh_authorized_keys:
          - ${sshKey}
    ssh_pwauth: false
    apt:
      primary:
        - arches: [default]
          uri: http://mirrors.ustc.edu.cn/debian
      security:
        - arches: [default]
          uri: http://mirrors.ustc.edu.cn/debian-security
    # The base image has no sshd; cloud-init installs it on first boot.
    packages:
      - auto-apt-proxy
      - avahi-daemon
      - avahi-utils
      - openssh-server
  '';
  mkIncusVm = spec: {
    image = "debian/13/cloud";
    inherit (spec) staticLease;
    devices.eth0 = {
      inherit (spec) hwaddr parent;
    };
    devices.root =
      {size = spec.rootSize;}
      // (
        if spec.stateful or false
        then {"size.state" = spec.memory;}
        else {}
      );
    config =
      {
        "security.secureboot" = "false";
        "limits.cpu" = toString spec.cpu;
        "limits.memory" = spec.memory;
        "cloud-init.user-data" = userData;
      }
      // (
        if spec.stateful or false
        then {
          "migration.stateful" = "true";
          "boot.host_shutdown_action" = "stateful-stop";
        }
        else {}
      );
  };
in {
  debian42 = mkIncusVm {
    # dnsmasq pins 100.65.2.42 to this MAC (dhcp-host, see networking.nix).
    staticLease = "100.65.2.42";
    hwaddr = "52:54:00:de:b1:42";
    parent = "br-gnet";
    rootSize = "510GiB";
    stateful = true;
    cpu = 16;
    memory = "16GiB";
  };
}
