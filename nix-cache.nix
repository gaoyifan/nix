{
  inherit ((import ./flake.nix).nixConfig) extra-substituters extra-trusted-public-keys;

  # Lower values are preferred, so the official cache is the last fallback.
  official-substituter = "https://cache.nixos.org?priority=100";
  official-public-key = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
}
