{
  lib,
  username,
  ...
}: let
  cacheSettings = import ../nix-cache.nix;
in {
  users.users.${username} = {
    home = "/Users/${username}";
    openssh.authorizedKeys.keys = [(import ../nixos/common/ssh-keys.nix).userKeys."yifan-macbook"];
  };

  nix.enable = false;
  environment.etc."nix/nix.custom.conf".text = ''
    experimental-features = nix-command flakes
    extra-substituters = ${lib.concatStringsSep " " cacheSettings.extra-substituters}
    extra-trusted-public-keys = ${lib.concatStringsSep " " cacheSettings.extra-trusted-public-keys}
    extra-trusted-users = ${username}
  '';

  networking = {
    computerName = "Hackintosh";
    hostName = "Hackintosh";
  };

  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
    '';
  };

  power.sleep = {
    computer = "never";
    display = "never";
    harddisk = "never";
    allowSleepByPowerButton = false;
  };

  system = {
    primaryUser = username;
    stateVersion = 6;
    defaults = {
      dock = {
        autohide = true;
        launchanim = false;
        magnification = false;
      };
      loginwindow = {
        autoLoginUser = username;
        GuestEnabled = false;
        SleepDisabled = true;
      };
      NSGlobalDomain = {
        NSAutomaticWindowAnimationsEnabled = false;
      };
      screensaver = {
        askForPassword = false;
      };
      universalaccess = {
        reduceMotion = true;
        reduceTransparency = true;
      };
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
      CustomSystemPreferences."com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        CriticalUpdateInstall = true;
        ConfigDataInstall = true;
      };
      CustomUserPreferences = {
        "com.apple.assistant.support"."Assistant Enabled" = false;
        "com.apple.screensaver".idleTime = 0;
      };
    };
  };

  system.activationScripts.postActivation.text = lib.mkAfter ''
    /usr/bin/mdutil -i off /nix >/dev/null 2>&1 || true
  '';
}
