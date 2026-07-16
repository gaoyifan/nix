# somo-minisforum - Minisforum mini PC, always-on Incus (KVM) host.
{lib, ...}: {
  imports = [
    ../../optional/bare-metal.nix
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
    ./wg-el2.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = ["mt7921e"];
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.max_pool_percent=10"
    "zswap.compressor=zstd"
  ];
  boot.kernel.sysctl."vm.swappiness" = 60;

  fileSystems."/".options = ["compress=zstd" "noatime"];

  hardware.enableRedistributableFirmware = true;

  environment.interactiveShellInit = ''
    export PATH="$HOME/.local/share/nix-lazy-apps/bin:$PATH"
  '';

  # This host cannot reach cache.nixos.org reliably: prefer Chinese mirrors
  # instead (SJTU covers paths USTC's sync lags on), keep the personal cache
  # for custom overlay packages, and leave cache.nixos.org as the last fallback.
  nix.settings = {
    max-jobs = 16;
    substituters = lib.mkForce [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://nix-cache.yfgao.net?priority=50"
      "https://cache.nixos.org?priority=100"
    ];
    trusted-public-keys = [
      "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
    ];
  };

  system.stateVersion = "26.05";
}
