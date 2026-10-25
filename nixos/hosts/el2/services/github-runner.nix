{
  imports = [
    (import ./github-runner/nspawn.nix {
      name = "github-runner-el2";
      root = "/pool1/services/github-runner/root";
      tokenFile = "/var/lib/github-runner-el2/token";
      guestModule = ./github-runner/runner-system.nix;
      nspawnArgs = ["--resolv-conf=bind-host --link-journal=try-guest"];
    })
  ];
  systemd.services.github-runner-el2 = {
    description = "GitHub Actions runner in a persistent systemd-nspawn container";
    serviceConfig = {
      MemoryHigh = "48G";
      MemoryMax = "64G";
    };
  };
}
