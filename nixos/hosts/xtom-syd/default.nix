{...}: {
  imports = [../xtom];

  networking.hostName = "xtom-syd";

  systemd.network.networks."10-wan" = {
    address = ["103.136.144.12/24"];
    routes = [
      {
        Gateway = "103.136.144.1";
        GatewayOnLink = true;
      }
    ];
  };
}
