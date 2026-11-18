{
  config,
  inputs,
  lib,
  ...
}: {
  imports = [inputs.codex-api.nixosModules.default];

  # Keep the package in the CI-built host closure when secrets are unavailable.
  system.extraDependencies = [config.services.codex-api.package];

  services.codex-api = lib.mkIf config.services.secrets.hasRealFiles {
    enable = true;
    settings = {
      upstream.supports_websockets = true;
      server.enable_websockets = true;
    };
  };
}
