{
  config,
  username,
  ...
}: let
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [
    ../../optional/acme-certificates.nix
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "blog";
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
  };

  systemd.network.networks."10-wan" = {
    matchConfig.Name = "ens5";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200n8"
    ];
  };

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  users.users = {
    ${username}.uid = 1000;
    root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILkaJyRHWai1ZQlQ+FybYHB2k/kl5JOfj+U8t70FY8qH internal-service"
    ];
  };

  services = {
    acmeCertificates = {
      enable = true;
      restartServices = [
        "podman-blog"
        "podman-light-single"
      ];
    };
    resticBackup.extraPaths = ["/var/lib/blog"];
    tmate-ssh-server = {
      enable = true;
      host = "tmate.yfgao.com";
      port = 2222;
      advertisedPort = 2222;
    };
  };

  virtualisation = {
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    oci-containers.containers = {
      blog-mysql = {
        # mariadb:10 — MariaDB 10.11.14
        image = "localhost/mariadb@sha256:18d9249799af40b63c12bfbb190fb10fcfa30026ef205d4b139ecba037a540de";
        volumes = [
          "/srv/docker/blog/mysql/data:/var/lib/mysql"
          "/srv/docker/blog/mysql/conf.d:/etc/mysql/conf.d"
        ];
        environment = {
          MYSQL_DATABASE = "wordpress";
          TZ = "Asia/Shanghai";
        };
        environmentFiles = ["/var/lib/blog/mysql.env"];
        extraOptions = [
          "--memory=1g"
          "--network-alias=blog-mysql"
        ];
      };
      blog-php = {
        # Official wordpress:php8.2-fpm — PHP 8.2.35.
        image = "docker.io/library/wordpress@sha256:f92d17271a6bdaffe116d59e3fc7209aeb60d96bc960cafc8a6e092db109973a";
        dependsOn = ["blog-mysql"];
        workdir = "/var/www/public";
        volumes = ["/srv/docker/blog/www:/var/www/public"];
        environment.TZ = "Asia/Shanghai";
        extraOptions = [
          "--memory=1g"
          "--network-alias=blog-php"
        ];
      };
      blog = {
        # Official nginx:stable-alpine — nginx 1.30.6 with HTTP/3.
        image = "docker.io/library/nginx@sha256:959ae6b898852db82e5b29b929388e59914f42be0a8f4d44c89a4c1f53b49208";
        dependsOn = ["blog-php"];
        ports = [
          "10080:80"
          "10443:443"
          "10443:443/udp"
        ];
        volumes = [
          "/srv/docker/blog/www:/var/www/public:ro"
          "/srv/docker/blog/log/nginx:/var/log/nginx"
          "${./nginx.conf.template}:/etc/nginx/templates/nginx.conf.template:ro"
          "${certDir}:/etc/ssl/private:ro"
        ];
        environment = {
          TZ = "Asia/Shanghai";
          NGINX_ENTRYPOINT_LOCAL_RESOLVERS = "1";
          NGINX_ENVSUBST_OUTPUT_DIR = "/etc/nginx";
        };
        extraOptions = ["--memory=1g"];
      };
      light-single = {
        # gaoyifan/light-server:single — OpenResty 1.19.3.2
        image = "localhost/gaoyifan/light-server@sha256:b45f7b62a728ceba5c1e1465ff4bfcc5105d697fd8726873712f749efa6f1d89";
        volumes = ["${certDir}:/usr/local/openresty/nginx/conf/ssl:ro"];
        extraOptions = ["--network=host"];
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/docker/blog/log 0755 root root -"
    "d /srv/docker/blog/log/nginx 0755 root root -"
    "d /srv/docker/blog/mysql/conf.d 0755 root root -"
    "d /srv/docker/blog/mysql/data 0755 root root -"
    "d /srv/docker/blog/www 0755 root root -"
    "d /var/lib/blog 0700 root root -"
  ];

  system.stateVersion = "26.05";
}
