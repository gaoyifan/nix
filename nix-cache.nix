{
  extra-substituters = [
    "https://nix-cache.yfgao.net?priority=50"
  ];
  extra-trusted-public-keys = [
    "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
  ];

  # Lower values are preferred, so the official cache is the last fallback.
  official-substituter = "https://cache.nixos.org?priority=100";
  official-public-key = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
}
