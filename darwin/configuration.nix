# Darwin system configuration
{
  darwinProfile ? "default",
  inputs,
  pkgs,
  username,
  ...
}: let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  defaultHomebrew = import ./homebrew/default.nix;
  openclawHomebrew = import ./homebrew/openclaw.nix;
in {
  # User configuration - required for home-manager
  users.users.${username}.home = "/Users/${username}";

  # Nix settings - system-wide configuration
  nix = {
    enable = false;
    settings = {
      # Trusted users for the nix daemon
      trusted-users = [
        "root"
        username
      ];

      # Enable experimental features
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Automatically accept flake config (extra-substituters, etc.)
      accept-flake-config = true;
    };
  };

  # Add homebrew bins to PATH for global tools
  environment.systemPath = [
    "/opt/homebrew/opt/rustup/bin"
    "/opt/homebrew/opt/node/bin"
    "/Users/${username}/.lmstudio/bin"
  ];
  environment.systemPackages = with pkgs; [
    just # Command runner
    nil # Nix language server
    unstablePkgs.bun # Fast JavaScript package manager
  ];

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

  homebrew =
    {
      enable = true;
      onActivation = {
        autoUpdate = true;
        cleanup = "uninstall";
      };
    }
    // (
      if darwinProfile == "openclaw"
      then openclawHomebrew
      else defaultHomebrew
    );
}
