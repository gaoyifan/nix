{
  imports = [../../../optional/github-runner/nspawn.nix];
  services.github-runner-nspawn.github-runner-el2 = {
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    root = "/pool1/services/github-runner/root";
    tokenFile = "/var/lib/github-runner-el2/token";
    buildUsersUidBase = 40000;
    guestModule = ./github-runner/runner-system.nix;
    nspawnArgs = ["--resolv-conf=replace-host --link-journal=try-guest"];
  };
  systemd.services.github-runner-el2 = {
    description = "GitHub Actions runner in a persistent systemd-nspawn container";
    serviceConfig = {
      MemoryHigh = "48G";
      MemoryMax = "64G";
    };
  };
}
