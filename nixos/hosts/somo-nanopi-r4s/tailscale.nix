{config, ...}: {
  services.tailscale = {
    enable = true;
    authKeyFile = "${config.services.secrets.filesDir}/nixos/somo-nanopi-r4s/tailscale-auth-key";
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--accept-dns=false"
      "--accept-routes"
      "--advertise-exit-node"
      "--advertise-routes=100.65.12.0/24,100.65.13.0/24"
      "--netfilter-mode=off"
      "--snat-subnet-routes=false"
    ];
  };
}
