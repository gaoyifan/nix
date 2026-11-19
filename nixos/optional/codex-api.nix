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
      fallback_model = "gpt-6.1-terra";
      upstream.supports_websockets = true;
      server.enable_websockets = true;
    };
  };
}
