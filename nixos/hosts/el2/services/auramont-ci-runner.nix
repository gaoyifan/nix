{lib, ...}: let
  runners = [
    # Keep the first runner's existing identity, root and caches.
    {
      suffix = "";
      buildUsersUidBase = 41000;
      machine = "auramont-ci";
      address = "100.64.2.82/24";
    }
    {
      suffix = "-2";
      buildUsersUidBase = 42000;
      machine = "auramont-ci2";
      address = "100.64.2.83/24";
    }
    {
      suffix = "-3";
      buildUsersUidBase = 43000;
      machine = "auramont-ci3";
      address = "100.64.2.84/24";
    }
    {
      suffix = "-4";
      buildUsersUidBase = 44000;
      machine = "auramont-ci4";
      address = "100.64.2.85/24";
    }
  ];
in {
  imports = [../../../optional/github-runner/nspawn.nix];
  services.github-runner-nspawn = lib.listToAttrs (map (runner:
    lib.nameValuePair "github-runner-auramont${runner.suffix}" {
      wantedBy = ["el2-services.target"];
      requires = ["zfs-unlock-mount.service"];
      inherit (runner) machine buildUsersUidBase;
      root = "/pool1/services/auramont-runner${runner.suffix}/root";
      tokenFile = "/var/lib/github-runner-auramont${runner.suffix}/token";
      guestModule = import ./auramont-runner/runner-system.nix {
        inherit (runner) machine address;
        runnerName = "el2-auramont${runner.suffix}";
      };
      nspawnArgs = [
        "--network-bridge=br-core --resolv-conf=off --link-journal=try-guest"
        "--capability=CAP_NET_ADMIN"
        # runc installs cgroup-v2 device rules through BPF.
        "--system-call-filter=bpf"
        # MongoDB locks SCRAM credentials within the guest's existing memlock limit.
        "--system-call-filter=mlock"
        "--system-call-filter=munlock"
      ];
    })
  runners);
  networking.homeRouter.switch.ports = lib.listToAttrs (map (runner:
    lib.nameValuePair "vb-${runner.machine}" {untagged = 642;})
  runners);
  systemd.services = lib.listToAttrs (map (runner:
    lib.nameValuePair "github-runner-auramont${runner.suffix}" {
      description = "Auramont GitHub Actions runner in an isolated nspawn container";
      serviceConfig = {
        MemoryHigh = "24G";
        MemoryMax = "32G";
        CPUQuota = "800%";
      };
    })
  runners);
}
