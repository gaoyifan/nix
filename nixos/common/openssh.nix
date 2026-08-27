# SSH server settings shared by all hosts.
{config, ...}: {
  services.fail2ban.enable = config.networking.firewall.enable || config.networking.nftables.enable;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
}
