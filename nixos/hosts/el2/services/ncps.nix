{
  networking.edgeFirewall.extraPublicTcpPorts = ["8501"];

  services.ncps = {
    enable = true;
    analytics.reporting.enable = false;
    cache = {
      hostName = "ncps";
      storage.local = "/pool1/nix-cache";
      maxSize = "45G";
      lru.schedule = "0 11 * * *";
      signNarinfo = false;
      upstream = {
        urls = [
          "https://nix-cache.yfgao.net"
          "https://cache.nixos.org"
        ];
        publicKeys = [
          "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        ];
      };
    };
  };
}
