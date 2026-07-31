{...}: {
  imports = [../xtom];

  networking.hostName = "xtom-hkg";

  systemd.network.networks."10-wan" = {
    address = ["103.125.232.15/24"];
    routes = [
      {
        Gateway = "103.125.232.1";
        GatewayOnLink = true;
      }
    ];
  };
}
