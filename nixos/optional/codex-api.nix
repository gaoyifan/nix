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
      model_prices."gpt-6.1-terra" = {
        input_usd_per_million = "1.00";
        cached_input_usd_per_million = "0.05";
        output_usd_per_million = "5.00";
      };
    };
  };
}
