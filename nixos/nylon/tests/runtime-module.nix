{
  inputs,
  nylonFixture,
  pkgs,
  ...
}: {
  imports = [
    inputs.agenix.nixosModules.default
    inputs.wlt.nixosModules.default
    ../module.nix
  ];

  networking.hostName = nylonFixture.selectorHost;

  services = {
    nylon = {
      enable = true;
      compiled = nylonFixture.selector;
    };
    wlt = {
      enable = true;
      configFile = pkgs.writeText "wlt-fixture.toml" "";
    };
  };

  # The check only evaluates the real runtime module. This test-owned source
  # satisfies agenix's source/path contract without consulting production
  # ciphertext or pretending that public fallback secrets exist.
  age.secrets.nylon-private-key.file =
    pkgs.writeText "nylon-runtime-module-fixture.age" "evaluation-only fixture\n";

  system.stateVersion = "26.05";
}
