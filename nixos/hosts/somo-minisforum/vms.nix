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

  incus = "${config.virtualisation.incus.package}/bin/incus";

  qemuConf = ''
    [object "mem0"]
    share = "off"
    merge = "on"
  '';
  vmSpec =
    lib.mapAttrs (_: vm: {
      inherit (vm) image;
      config = vm.config // {"raw.qemu.conf" = qemuConf;};
      devices = vm.devices or {};
    })
    vms;
  vmSpecFile = pkgs.writeText "incus-vms.json" (builtins.toJSON vmSpec);

  applyDeclarativeVms = pkgs.writeShellScriptBin "incus-apply-declarative-vms" ''
    export INCUS=${lib.escapeShellArg incus}
    export IMAGE_REMOTE=${lib.escapeShellArg imageRemote}
    export IMAGE_REMOTE_URL=${lib.escapeShellArg imageRemoteUrl}
    export VM_SPEC=${vmSpecFile}
    exec ${pkgs.ruby}/bin/ruby ${./incus-apply-declarative-vms.rb} "$@"
  '';
in {
  environment.systemPackages = [applyDeclarativeVms];

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
}
