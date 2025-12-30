# Darwin system configuration
{
  pkgs,
  lib,
  username,
  ...
}: {
  # User configuration - required for home-manager
  users.users.${username}.home = "/Users/${username}";

  # Nix settings - system-wide configuration
  nix = {
    settings = {
      # Binary cache configuration
      substituters = ["https://cache.nixos.org" "https://nix-cache.yfgao.net"];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
      ];

      # Trusted users for the nix daemon
      trusted-users = ["root" username];

      # Enable experimental features
      experimental-features = ["nix-command" "flakes"];

      # Automatically accept flake config (extra-substituters, etc.)
      accept-flake-config = true;
    };

    # Garbage collection
    gc.automatic = true;

    # Optimize store
    optimise.automatic = true;
  };

  system = {
    # Used for backwards compatibility
    stateVersion = 6;

    # Disable startup chime
    startup.chime = false;
  };

  # Enable Touch ID authentication for sudo
  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
  };
}
