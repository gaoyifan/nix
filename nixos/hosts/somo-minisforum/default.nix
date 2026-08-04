# somo-minisforum - Minisforum mini PC, always-on Incus (KVM) host.
{config, ...}: let
  newApiTokenDirectory = builtins.path {
    path = config.services.secrets.filesDir + "/nixos/somo-minisforum/new-api-tokens";
    name = "hermes-new-api-tokens";
  };
in {
  imports = [
    ../../optional/bare-metal.nix
    ../../optional/hermes-nspawn.nix
    ./hardware-configuration.nix
    ./networking.nix
    ./virtualisation.nix
    ./graphics.nix
    ./bees.nix
    ./ksm.nix
    ./vms.nix
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
    containers = config.services.secrets.nixos."somo-minisforum".hermesNspawn;
    inherit newApiTokenDirectory;
    dashboardDomain = "hermes.dengdengli.com";
    honcho = {
      newApiTokenFile = "${newApiTokenDirectory}/honcho";
    };
    telegramBotApi = {
      enable = true;
      inherit (config.services.secrets.nixos."somo-minisforum".telegramBotApi) apiId apiHash;
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
