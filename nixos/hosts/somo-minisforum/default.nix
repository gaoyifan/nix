# somo-minisforum - Minisforum mini PC, always-on Incus (KVM) host.
{
  config,
  lib,
  ...
}: let
  filesDir = config.services.secrets.filesDir;
  tokenDirectory = filesDir + "/nixos/somo-minisforum/new-api-tokens";
  newApiTokenDirectory = "/run/agenix/new-api-tokens";
  newApiTokens =
    if config.services.secrets.hasRealFiles
    then
      lib.mapAttrs' (fileName: _: let
        tokenName = lib.removeSuffix ".age" fileName;
      in
        lib.nameValuePair tokenName {
          file = tokenDirectory + "/${fileName}";
          path = "${newApiTokenDirectory}/${tokenName}";
        })
      (lib.filterAttrs (name: _: lib.hasSuffix ".age" name) (builtins.readDir tokenDirectory))
    else {};
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles (
    {
      telegram-api-hash.file = filesDir + "/nixos/somo-minisforum/telegram-api-hash.age";
    }
    // lib.mapAttrs' (tokenName: secret:
      lib.nameValuePair "new-api-token-${tokenName}" secret)
    newApiTokens
  );

  imports = [
    ../../optional/bare-metal.nix
    ../../optional/hermes-nspawn.nix
    ./hardware-configuration.nix
    ./networking.nix
    ./virtualisation.nix
    ./graphics.nix
    ./bees.nix
    ./ksm.nix
    ./apt-cacher-ng.nix
    ./newapi.nix
    ./whisper-server.nix
    ./wifi-ap.nix
    ./tailscale.nix
    ./wg-iplc.nix
  ];

  services.hermes-nspawn = {
    enable = true;
    defaultLan = "somo";
    containers = import (filesDir + "/nixos/somo-minisforum/hermes-nspawn.nix");
    inherit newApiTokenDirectory;
    newApiTokenRestartTriggers = lib.mapAttrs (_: secret: secret.file) newApiTokens;
    dashboardDomain = "hermes.dengdengli.com";
    honcho = {
      newApiTokenFile = "${newApiTokenDirectory}/honcho";
      newApiTokenFileSource = lib.attrByPath ["honcho" "file"] null newApiTokens;
    };
    telegramBotApi = {
      enable = true;
      inherit (import (filesDir + "/nixos/somo-minisforum/telegram-bot-api.nix")) apiId;
      apiHashEnvironmentFile = "/run/agenix/telegram-api-hash";
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = ["mt7921e"];
  boot.kernelParams = [
    "nosmt"
    "zswap.enabled=1"
    "zswap.max_pool_percent=10"
    "zswap.compressor=zstd"
  ];
  boot.kernel.sysctl."vm.swappiness" = 60;

  boot.kernel.sysfs.kernel.mm.transparent_hugepage = {
    shmem_enabled = "advise";
    defrag = "never";
  };

  fileSystems."/".options = ["compress=zstd" "noatime"];

  hardware.enableRedistributableFirmware = true;

  environment.interactiveShellInit = ''
    export PATH="$HOME/.local/share/nix-lazy-apps/bin:$PATH"
  '';

  nix.settings.max-jobs = 16;

  system.stateVersion = "26.05";
}
