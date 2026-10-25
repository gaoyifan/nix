{
  imports = [
    (import ./github-runner/nspawn.nix {
      name = "github-runner-auramont";
      machine = "auramont-ci";
      root = "/pool1/services/auramont-runner/root";
      tokenFile = "/var/lib/github-runner-auramont/token";
      guestModule = ./auramont-runner/runner-system.nix;
      nspawnArgs = [
        "--network-bridge=br-core --resolv-conf=off --link-journal=try-guest"
        "--capability=CAP_NET_ADMIN"
        # runc installs cgroup-v2 device rules through BPF.
        "--system-call-filter=bpf"
      ];
    })
  ];
  networking.homeRouter.switch.ports.vb-auramont-ci.untagged = 642;
  systemd.services.github-runner-auramont = {
    description = "Auramont GitHub Actions runner in an isolated nspawn container";
    serviceConfig = {
      MemoryHigh = "24G";
      MemoryMax = "32G";
      CPUQuota = "1200%";
    };
  };
}
