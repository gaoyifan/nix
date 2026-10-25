{
  imports = [../../../optional/acme-certificates.nix];

  services.acmeCertificates = {
    enable = true;
    restartServices = [
      "derp"
      "podman-light-single"
      "tailscale-serve"
    ];
  };
}
