{
  # cache.nixos.org remains Nix's built-in fallback.
  extra-substituters = [
    "https://nix-cache.yfgao.net?priority=50"
  ];
  extra-trusted-public-keys = [
    "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
  ];
}
