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

  mkVmCommands = name: vm: ''
    if ! ${incus} info ${name} >/dev/null 2>&1; then
      echo "Creating VM ${name} from ${imageRemote}:${vm.image}"
      ${incus} init ${imageRemote}:${vm.image} ${name} --vm
    fi
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
        key: value: ''${incus} config set ${name} "${key}=${value}"''
      )
      vm.config)}
    if [ "$(${incus} list ${name} -c s -f csv)" != "RUNNING" ]; then
      ${incus} start ${name}
    fi
  '';

  applyVms = pkgs.writeShellScript "incus-apply-vms" ''
    set -euo pipefail

    if ! ${incus} info >/dev/null 2>&1; then
      echo "Incus is not ready; skipping declarative VM setup"
      exit 0
    fi

    if ! ${incus} remote list -f csv | cut -d, -f1 | grep -qx "${imageRemote}"; then
      ${incus} remote add ${imageRemote} ${imageRemoteUrl} --protocol=simplestreams --public
    fi

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList mkVmCommands vms)}
  '';
in {
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
    script = "${applyVms}";
  };
}
