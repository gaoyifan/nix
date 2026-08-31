# SSH server settings shared by all hosts.
{
  config,
  lib,
  ...
}: let
  ustcAddresses = lib.filter (line: line != "" && !lib.hasPrefix "#" line) (
    lib.splitString "\n" (builtins.readFile ../../pkgs/nft-geo-sets/ustc.txt)
  );
  penaltyExemptAddresses =
    ustcAddresses
    ++ [
      "10.0.0.0/8"
      "100.64.0.0/10"
      "172.16.0.0/12"
      "192.168.0.0/16"
    ];
in {
  services.fail2ban.enable = config.networking.firewall.enable || config.networking.nftables.enable;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PerSourceMaxStartups = 3;
      PerSourceNetBlockSize = "22:48";
      PerSourcePenaltyExemptList = lib.concatStringsSep "," penaltyExemptAddresses;
    };
  };
}
