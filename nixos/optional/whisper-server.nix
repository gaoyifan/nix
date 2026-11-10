{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.whisper-server;
  tmpDir = "/run/whisper-server";
in {
  options.services.whisper-server = {
    enable = lib.mkEnableOption "whisper.cpp HTTP transcription server";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address on which the transcription server listens.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "HTTP port of the transcription server.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.whisper-server = {
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];
      path = [pkgs.ffmpeg];
      serviceConfig = {
        RuntimeDirectory = "whisper-server";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = tmpDir;
        ExecStart = "${pkgs.whisper-cpp}/bin/whisper-server -m ${pkgs.whisper-large-v3-turbo} -l zh -t 16 -ng --host ${cfg.listenAddress} --port ${toString cfg.port} --convert --tmp-dir ${tmpDir}";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "30s";
      };
    };
  };
}
