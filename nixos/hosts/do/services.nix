{...}: {
  services = {
    journald.extraConfig = "SystemMaxUse=256M";
    nginx = {
      enable = true;
      virtualHosts = {
        default = {
          default = true;
          locations."/".return = "404";
        };
        "xuhao1.com" = {
          serverAliases = [
            "*.xuhao1.com"
            "xuhao1.space"
            "*.xuhao1.space"
            "xuhao1.me"
            "*.xuhao1.me"
            "louyu.me"
            "*.louyu.me"
            "fiona-louyu.me"
            "*.fiona-louyu.me"
          ];
          extraConfig = "client_max_body_size 256m;";
          locations."/" = {
            proxyPass = "http://100.64.1.30:80/";
            proxyWebsockets = true;
          };
        };
      };
    };
  };
}
