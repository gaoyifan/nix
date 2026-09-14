{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  sshKey = (import ../../common/ssh-keys.nix).userKeys."yifan-macbook";
  pveEdk2Share = "${pkgs.pve-edk2-firmware-ovmf}/usr/share/pve-edk2-firmware";
  ovmf2MB = pkgs.OVMF.override {
    secureBoot = true;
    fdSize2MB = true;
  };
  macosStateDir = "/var/lib/incus-macos";
  incusEdk2 = pkgs.linkFarm "incus-pve-ovmf" [
    {
      name = "OVMF_CODE.fd";
      path = "${ovmf2MB.fd}/FV/OVMF_CODE.fd";
    }
    {
      name = "OVMF_VARS.fd";
      path = "${ovmf2MB.fd}/FV/OVMF_VARS.fd";
    }
    {
      name = "OVMF_VARS.ms.fd";
      path = "${ovmf2MB.fd}/FV/OVMF_VARS.fd";
    }
    {
      name = "OVMF_CODE.4MB.fd";
      path = "${pveEdk2Share}/OVMF_CODE_4M.secboot.fd";
    }
    {
      name = "OVMF_VARS.4MB.fd";
      path = "${pveEdk2Share}/OVMF_VARS_4M.fd";
    }
    {
      name = "OVMF_VARS.4MB.ms.fd";
      path = "${pveEdk2Share}/OVMF_VARS_4M.ms.fd";
    }
    {
      name = "seabios.bin";
      path = "${pkgs.seabios-qemu}/share/seabios/bios.bin";
    }
  ];

  legacyVm = {
    macAddress,
    rootSize,
    cpu,
    memory,
    extraDevices ? {},
    rootPool ? "default",
  }: {
    inherit macAddress rootSize extraDevices rootPool;
    vlan = 642;
    rootConfig = {
      "boot.priority" = "10";
      "io.bus" = "virtio-scsi";
    };
    config = {
      "limits.cpu" = cpu;
      "limits.memory" = memory;
      "security.csm" = "true";
      "security.secureboot" = "false";
    };
  };
in {
  imports = [../../optional/incus-vms];

  virtualisation.incusVms = {
    enable = true;
    metricsPort = 8444;
    pools = {
      default = {
        driver = "zfs";
        source = "pool1/incus";
      };
      pool0 = {
        driver = "zfs";
        source = "pool0/incus";
      };
    };
    requiredUnits = ["zfs-import-pool1.service"];

    instances.kingdee = {
      vlan = 642;
      macAddress = "CA:52:18:F3:D7:F4";
      dhcpAddress = "192.168.225.50";
      rootSize = "512GiB";
      rootConfig = {
        "boot.priority" = "10";
        "io.bus" = "virtio-scsi";
      };
      config = {
        "limits.cpu" = "8";
        "limits.memory" = "32GiB";
        "security.csm" = "true";
        "security.secureboot" = "false";
      };
      extraDevices.agent = {
        type = "disk";
        source = "agent:config";
      };
    };

    instances.debian23-openclaw = {
      vlan = 642;
      macAddress = "BC:24:11:2A:7D:8D";
      rootSize = "32GiB";
      rootConfig."boot.priority" = "10";
      config = {
        "limits.cpu" = "8";
        "limits.memory" = "16GiB";
        "security.csm" = "true";
        "security.secureboot" = "false";
      };
    };

    instances.git-automesh-org = legacyVm {
      macAddress = "BC:24:11:2D:50:BF";
      rootSize = "50GiB";
      cpu = "8";
      memory = "24GiB";
      rootPool = "pool0";
      extraDevices = {
        data = {
          type = "disk";
          pool = "pool0";
          source = "git-automesh-org-data";
        };
      };
    };

    instances.source-automesh-org = legacyVm {
      macAddress = "BC:24:11:5D:13:8A";
      rootSize = "20GiB";
      cpu = "8";
      memory = "16GiB";
      rootPool = "pool0";
      extraDevices = {
        data = {
          type = "disk";
          pool = "pool0";
          source = "source-automesh-org-data";
        };
      };
    };

    instances.debian21 = legacyVm {
      macAddress = "BC:24:11:9F:EE:B3";
      rootSize = "40GiB";
      cpu = "20";
      memory = "32GiB";
      rootPool = "pool0";
      extraDevices = {
        data1 = {
          type = "disk";
          pool = "pool0";
          source = "debian21-srv";
        };
        data2 = {
          type = "disk";
          pool = "pool0";
          source = "debian21-docker";
        };
      };
    };

    instances.debian24-openclaw-aran = legacyVm {
      macAddress = "BC:24:11:2A:77:F1";
      rootSize = "50GiB";
      cpu = "16";
      memory = "16GiB";
    };

    instances.debian41 = legacyVm {
      macAddress = "BC:24:11:6D:1C:82";
      rootSize = "100GiB";
      cpu = "40";
      memory = "32GiB";
    };

    instances.xuhao = {
      image = "debian/13/cloud";
      vlan = 642;
      macAddress = "52:54:00:64:02:30";
      dhcpAddress = "100.64.2.30";
      rootSize = "20GiB";
      headless = true;
      config = {
        "limits.cpu" = "4";
        "limits.memory" = "4GiB";
        "security.secureboot" = "false";
        "cloud-init.user-data" = ''
          #cloud-config
          users:
            - name: root
              lock_passwd: false
              hashed_passwd: "*"
              ssh_authorized_keys:
                - ${sshKey}
          ssh_pwauth: false
          packages:
            - openssh-server
        '';
      };
    };

    instances.debian43 = legacyVm {
      macAddress = "BC:24:11:C5:76:8C";
      rootSize = "40GiB";
      cpu = "4";
      memory = "16GiB";
    };

    instances.debian52 = legacyVm {
      macAddress = "BC:24:11:95:83:D8";
      rootSize = "10GiB";
      cpu = "4";
      memory = "4GiB";
    };

    instances.debian70-zdgroup = legacyVm {
      macAddress = "BC:24:11:41:DF:6F";
      rootSize = "20GiB";
      cpu = "8";
      memory = "8GiB";
    };

    instances.windows60 = {
      vlan = 642;
      macAddress = "BC:24:11:D9:BB:7D";
      rootSize = "64GiB";
      rootConfig = {
        "boot.priority" = "10";
        "io.bus" = "virtio-scsi";
        "io.cache" = "unsafe";
      };
      config = {
        "limits.cpu" = "8";
        "limits.memory" = "16GiB";
        "security.csm" = "false";
        "security.secureboot" = "true";
        "raw.qemu.conf" = ''
          [machine]
          type = "pc-q35-10.1"
        '';
      };
      extraDevices = {
        agent = {
          type = "disk";
          source = "agent:config";
        };
        downloads = {
          type = "disk";
          source = "/pool0/media1/downloads";
          path = "/mnt/downloads";
          "io.bus" = "virtiofs";
        };
        tpm.type = "tpm";
      };
    };

    instances.hackintosh = {
      vlan = 642;
      macAddress = "00:16:CB:64:02:80";
      dhcpAddress = "100.64.2.80";
      rootSize = "128GiB";
      rootConfig = {
        "io.bus" = "virtio-blk";
      };
      extraDevices.photos = {
        type = "disk";
        pool = "pool0";
        source = "hackintosh-photos";
      };
      config = {
        "boot.autostart" = "true";
        "limits.cpu" = "sockets=1,cores=4,threads=1";
        "limits.memory" = "8GiB";
        "limits.memory.hotplug" = "false";
        "raw.apparmor" = "/dev/zero k,";
        "raw.qemu.scriptlet" = builtins.readFile ./hackintosh-qemu-scriptlet.py;
        "security.secureboot" = "false";
      };
    };
  };

  users.users.${username}.extraGroups = [
    "docker"
    "incus-admin"
  ];

  virtualisation.docker.enable = true;
  environment.systemPackages = [
    pkgs.docker-compose
    pkgs.x11vnc
  ];

  systemd.tmpfiles.rules = [
    "d ${macosStateDir} 0700 root root -"
    "z ${macosStateDir}/OpenCore.raw 0600 root root -"
    "z ${macosStateDir}/smbios.json 0600 root root -"
    "z ${macosStateDir}/vnc.pass 0600 root root -"
  ];

  services.resticBackup = {
    extraPaths = [macosStateDir];
    extraExcludes = ["${macosStateDir}/BaseSystem.img"];
  };

  systemd.services.incus.environment.INCUS_EDK2_PATH = lib.mkForce incusEdk2;

  systemd.services.hackintosh-vnc = {
    description = "VNC bridge for the Hackintosh Incus console";
    wantedBy = ["multi-user.target"];
    requires = ["incus.service"];
    after = ["incus.service"];
    path = [
      pkgs.coreutils
      pkgs.openbox
      pkgs.spice-gtk
      pkgs.x11vnc
      pkgs.xauth
      pkgs.xdpyinfo
      pkgs.xorg-server
    ];
    environment.DISPLAY = ":91";
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      RuntimeDirectory = "hackintosh-vnc";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = "${pkgs.coreutils}/bin/test -r ${macosStateDir}/vnc.pass";
    };
    script = ''
      set -euo pipefail

      export HOME="$RUNTIME_DIRECTORY"
      export XAUTHORITY="$HOME/Xauthority"
      xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 \
        "$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
      chmod 0600 "$XAUTHORITY"

      Xvfb "$DISPLAY" -auth "$XAUTHORITY" -screen 0 1280x800x24 -nolisten tcp &
      xvfb_pid=$!
      trap 'kill "''${x11vnc_pid:-}" "''${spicy_pid:-}" "''${openbox_pid:-}" "$xvfb_pid" 2>/dev/null || true' EXIT

      until xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; do
        kill -0 "$xvfb_pid"
        sleep 0.1
      done

      openbox --sm-disable &
      openbox_pid=$!

      until [[ -S /run/incus/hackintosh/qemu.spice ]]; do
        sleep 2
      done

      spicy --uri="spice+unix:///run/incus/hackintosh/qemu.spice" --full-screen &
      spicy_pid=$!
      sleep 2

      x11vnc \
        -display "$DISPLAY" \
        -forever \
        -shared \
        -rfbauth ${macosStateDir}/vnc.pass \
        -rfbport 5900 \
        -rfbportv6 -1 \
        -listen 100.64.2.254 \
        -no6 \
        -noxdamage \
        -xkb &
      x11vnc_pid=$!

      wait -n "$x11vnc_pid" "$spicy_pid" "$openbox_pid" "$xvfb_pid"
    '';
  };

  systemd.services.start-pool0-dependent-vms = {
    description = "Restore Incus VMs that require manually unlocked pool0 datasets";
    wantedBy = ["el2-services.target"];
    requires = [
      "incus.service"
      "zfs-unlock-mount.service"
    ];
    after = [
      "incus.service"
      "zfs-unlock-mount.service"
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      for instance in hackintosh windows60; do
        if [[ "$(${config.virtualisation.incus.package}/bin/incus config get "$instance" volatile.last_state.power)" == RUNNING ]] \
          && [[ "$(${config.virtualisation.incus.package}/bin/incus list "$instance" --format csv -c s)" == STOPPED ]]; then
          ${config.virtualisation.incus.package}/bin/incus start "$instance"
        fi
      done
    '';
  };
}
