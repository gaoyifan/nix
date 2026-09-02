{
  virtualisation.oci-containers.containers.py-kms = {
    image = "ghcr.io/gaoyifan/py-kms@sha256:df7db624fa6f1d63e657b1f3d410048eacca9d7fa644d4426ea3007b8ea7fb3f";
    extraOptions = [
      "--init"
      "--network=host"
    ];
  };

  systemd.services.podman-py-kms.serviceConfig.SuccessExitStatus = 143;
}
