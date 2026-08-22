{
  config,
  lib,
  pkgs,
  ...
}: let
  mail = config.services.secrets.mail;
in {
  age.secrets.mailgun-smtp-password = lib.mkIf config.services.secrets.hasRealFiles {
    file = config.services.secrets.filesDir + "/nixos/mailgun-smtp-password.age";
  };

  programs.msmtp = {
    enable = true;
    defaults = {
      auth = true;
      syslog = true;
      tls = true;
    };
    accounts.default = {
      host = "smtp.mailgun.org";
      port = 587;
      user = mail.smtpUser;
      passwordeval = "${lib.getExe' pkgs.coreutils "cat"} /run/agenix/mailgun-smtp-password";
      from = mail.senders.${config.networking.hostName};
    };
  };

  services.znapzend.mailErrorSummaryTo = mail.znapzendErrorSummaryTo;
}
