{
  config,
  lib,
  ...
}: {
  imports = [../../../optional/acme-certificates.nix];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    acme-repository-pull-key.file = config.services.secrets.filesDir + "/nixos/acme-repository-pull-key.age";
  };

  services.acmeCertificates = {
    enable = true;
    restartServices = [
      "derp"
      "podman-light-single"
      "tailscale-serve"
    ];
  };
}
