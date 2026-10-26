{
  imports = [
    (import ../../optional/github-runner/nspawn.nix {
      name = "github-runner-auramont";
      machine = "auramont-ci";
      root = "/var/lib/auramont-runner/root";
      tokenFile = "/var/lib/github-runner-auramont/token";
      guestModule = ./auramont-runner-system.nix;
      nspawnArgs = ["--network-veth --resolv-conf=off --link-journal=try-guest"];
    })
  ];

  systemd.network.networks."20-auramont-ci" = {
    matchConfig.Name = "ve-auramont-ci";
    address = ["192.168.247.1/30"];
    networkConfig.IPMasquerade = "ipv4";
    linkConfig.RequiredForOnline = false;
  };
  systemd.services.github-runner-auramont = {
    description = "Auramont ARM64 GitHub Actions runner in an isolated nspawn container";
    serviceConfig = {
      CPUQuota = "300%";
      MemoryHigh = "10G";
      MemoryMax = "12G";
    };
  };
}
