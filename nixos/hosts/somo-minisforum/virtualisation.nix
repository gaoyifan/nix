{username, ...}: let
  sshKey = (import ../../common/ssh-keys.nix).userKeys."yifan-macbook";
  memory = "16GiB";
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
    packages:
      - auto-apt-proxy
      - avahi-daemon
      - avahi-utils
      - openssh-server
  '';
in {
  imports = [../../optional/incus-vms];

  virtualisation.incusVms = {
    enable = true;
    metricsPort = 8444;
    cacheReclaim = true;

    instances.debian42 = {
      image = "debian/13/cloud";
      vlan = 652;
      macAddress = "52:54:00:de:b1:42";
      dhcpAddress = "100.65.2.42";
      rootSize = "510GiB";
      rootConfig."size.state" = memory;
      headless = true;
      config = {
        "security.secureboot" = "false";
        "limits.cpu" = "16";
        "limits.memory" = memory;
        "cloud-init.user-data" = userData;
        "migration.stateful" = "true";
        "boot.host_shutdown_action" = "stateful-stop";
      };
    };
  };

  users.users.${username}.extraGroups = [
    "docker"
    "incus-admin"
  ];

  virtualisation.docker.enable = true;
}
