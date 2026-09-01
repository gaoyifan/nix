{
  config,
  lib,
  pkgs,
  ...
}: {
  services.bitmagnet = {
    enable = true;
    settings = {
      http_server.port = "127.0.0.1:3333";
      postgres = {
        user = "postgres";
      };
    };
  };

  services.postgresql = {
    package = pkgs.postgresql_16;
    identMap = lib.mkBefore ''
      postgres bitmagnet postgres
    '';
    settings = {
      shared_buffers = "10GB";
      work_mem = "256MB";
      maintenance_work_mem = "2GB";
      effective_cache_size = "18GB";
      random_page_cost = 1.1;
      effective_io_concurrency = 200;
      max_worker_processes = 4;
      max_parallel_workers = 4;
      max_parallel_workers_per_gather = 3;
    };
  };

  systemd.services.bitmagnet.serviceConfig.ExecStart = lib.mkForce ''
    ${lib.getExe config.services.bitmagnet.package} worker run --keys=http_server --keys=queue_server --keys=dht_crawler
  '';
}
