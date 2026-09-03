{
  config,
  username,
  ...
}: let
  hostname = "collie-el2.ts.gaof.net";
  url = "https://${hostname}";
  port = 8787;
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
  collieEnvironment = {
    COLLIE_ALLOWED_ORIGINS = url;
    COLLIE_MUX = "herdr";
    COLLIE_PORT = toString port;
    COLLIE_PUBLIC_HOSTS = hostname;
    COLLIE_PUBLIC_URL = url;
    COLLIE_SKIP_SERVE = "1";
  };
in {
  home-manager.users.${username} = {
    home.sessionVariables = collieEnvironment;
    systemd.user.sessionVariables = collieEnvironment;
  };

  services.tailscale.serve.services.collie-el2 = {
    certificate = {
      certFile = "${certDir}/fullchain.pem";
      keyFile = "${certDir}/privkey.pem";
    };
    tlsEndpoints."tcp:443" = "http://127.0.0.1:${toString port}";
  };
}
