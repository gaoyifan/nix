# SSH server settings shared by all hosts.
{
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      # Key-only root login is required for deploy-rs / remote nixos-rebuild.
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
}
