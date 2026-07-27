# Declarative Incus KVM virtual machines.
#
# Incus preseed (virtualisation.nix) only covers profiles/pools, not
# instances, so a oneshot service creates missing VMs and re-applies their
# config on every switch. Config drift on the declared keys is corrected;
# VMs removed from this file are left running (delete manually).
# Pattern borrowed from basnijholt's hosts/nas/virtualization.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # linuxcontainers.org image mirror reachable from mainland China.
  imageRemote = "nju-images";
  imageRemoteUrl = "https://mirror.nju.edu.cn/lxc-images/";

  vms = config.services.secrets.nixos."somo-minisforum".vms;

  nicHostName = vm: let
    mac = lib.replaceStrings [":"] [""] vm.devices.eth0.hwaddr;
  in "inc${builtins.substring 2 10 mac}";

  declaredVms =
    lib.mapAttrs
    (_: vm:
      vm
      // {
        devices =
          vm.devices
          // {
            eth0 = vm.devices.eth0 // {host_name = nicHostName vm;};
          };
      })
    vms;

  incus = "${config.virtualisation.incus.package}/bin/incus";

  # Remove desktop devices from headless server VMs.
  qemuConf = ''
    [object "mem0"]
    share = "off"
    merge = "on"

    [device "qemu_balloon"]
    free-page-reporting = "on"

    [machine]
    i8042 = "off"
    [device "qemu_gpu"]
    [device "qemu_keyboard"]
    [device "qemu_tablet"]
    [audiodev "qemu_sound-audiodev"]
    [device "qemu_sound"]
    [chardev "qemu_spice-chardev"]
    [device "qemu_spice"]
    [chardev "qemu_spicedir-chardev"]
    [device "qemu_spicedir"]
    [device "qemu_usb"]
    [chardev "qemu_spice-usb-chardev1"]
    [device "qemu_spice-usb1"]
    [chardev "qemu_spice-usb-chardev2"]
    [device "qemu_spice-usb2"]
    [chardev "qemu_spice-usb-chardev3"]
    [device "qemu_spice-usb3"]
  '';
  vmSpec =
    lib.mapAttrs (_: vm: {
      inherit (vm) image;
      config =
        vm.config
        // {
          # The reconciler must apply stopped-only settings before starting
          # VMs, so it is the sole owner of their startup lifecycle.
          "boot.autostart" = "false";
          "raw.qemu.conf" = qemuConf;
        };
      devices = vm.devices or {};
    })
    declaredVms;
  vmSpecFile = pkgs.writeText "incus-vms.json" (builtins.toJSON vmSpec);

  applyDeclarativeVms = pkgs.writeShellScriptBin "incus-apply-declarative-vms" ''
    export INCUS=${lib.escapeShellArg incus}
    export IMAGE_REMOTE=${lib.escapeShellArg imageRemote}
    export IMAGE_REMOTE_URL=${lib.escapeShellArg imageRemoteUrl}
    export VM_SPEC=${vmSpecFile}
    exec ${pkgs.ruby}/bin/ruby ${./incus-apply-declarative-vms.rb} "$@"
  '';

  dropVmCaches = pkgs.writeShellScriptBin "incus-drop-vm-caches-on-low-memory" ''
    export INCUS=${lib.escapeShellArg incus}
    exec ${pkgs.ruby}/bin/ruby ${./incus-drop-vm-caches-on-low-memory.rb}
  '';
in {
  environment.systemPackages = [applyDeclarativeVms dropVmCaches];

  systemd.network.networks =
    lib.mapAttrs'
    (name: vm:
      lib.nameValuePair "10-incus-${name}" {
        matchConfig.Name = nicHostName vm;
        networkConfig = {
          Bridge = vm.devices.eth0.parent;
          LinkLocalAddressing = false;
        };
        linkConfig.RequiredForOnline = "no";
      })
    declaredVms;

  systemd.services.incus-declarative-vms = {
    description = "Create and configure declarative Incus VMs";
    wants = ["incus.service" "network-online.target"];
    after = ["incus.service" "incus-preseed.service" "network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # First run downloads the VM image (~350 MB).
      TimeoutStartSec = "30min";
      # The incus CLI stores remotes in ~/.config/incus.
      Environment = ["HOME=/root"];
    };
    script = ''
      ${applyDeclarativeVms}/bin/incus-apply-declarative-vms --no-restart
    '';
  };

  systemd.services.incus-drop-vm-caches-on-low-memory = {
    description = "Drop Incus VM guest caches when host memory is low";
    wants = ["incus.service"];
    after = ["incus.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${dropVmCaches}/bin/incus-drop-vm-caches-on-low-memory";
    };
  };

  systemd.timers.incus-drop-vm-caches-on-low-memory = {
    description = "Check host memory pressure for Incus VM cache reclaim";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      AccuracySec = "10s";
    };
  };
}
