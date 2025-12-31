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

    # Primary user for nix-darwin (required for homebrew, etc.)
    primaryUser = username;

    # Disable startup chime
    startup.chime = false;
  };

  # Enable Touch ID authentication for sudo
  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
  };

  homebrew = {
    enable = true;
    onActivation.autoUpdate = true;
  };
}
