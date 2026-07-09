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
  ...
}: let
  # linuxcontainers.org image mirror reachable from mainland China.
  imageRemote = "nju-images";
  imageRemoteUrl = "https://mirror.nju.edu.cn/lxc-images/";

  vms = config.services.secrets.nixos."somo-minisforum".vms;

  incus = "${config.virtualisation.incus.package}/bin/incus";

  ksmQemuConf = ''
    [object "mem0"]
    share = "off"
    merge = "on"
  '';

  # `<get> <key>` / `<set> <key>=<value>`, only when the value differs.
  # Skipping no-op sets matters for keys that reject live updates (hwaddr,
  # shrinking limits.memory); escapeShellArg keeps multi-line values
  # (cloud-init.user-data) intact.
  mkSetCommands = get: set: attrs:
    lib.concatStringsSep "\n" (lib.mapAttrsToList (key: value: ''
        if [ "$(${get} ${key} 2>/dev/null)" != ${lib.escapeShellArg value} ]; then
          ${set} ${lib.escapeShellArg "${key}=${value}"}
        fi
      '')
      attrs);

  # Devices inherited from a profile (e.g. eth0) must be promoted to
  # instance-local ones before their keys can be overridden.
  mkDeviceCommands = name: dev: opts: ''
    if ! ${incus} config device list ${name} | grep -qx ${dev}; then
      ${incus} config device override ${name} ${dev}
    fi
    ${mkSetCommands "${incus} config device get ${name} ${dev}" "${incus} config device set ${name} ${dev}" opts}
  '';

  mkVmCommands = name: vm: ''
    if ! ${incus} info ${name} >/dev/null 2>&1; then
      echo "Creating VM ${name} from ${imageRemote}:${vm.image}"
      ${incus} init ${imageRemote}:${vm.image} ${name} --vm
    fi
    ${mkSetCommands "${incus} config get ${name}" "${incus} config set ${name}" (vm.config // {"raw.qemu.conf" = ksmQemuConf;})}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (mkDeviceCommands name) (vm.devices or {}))}
    if [ "$(${incus} list ${name} -c s -f csv)" != "RUNNING" ]; then
      ${incus} start ${name}
    fi
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
    script = ''
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
  };
}
