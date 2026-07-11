# whisper.cpp HTTP server for Hermes audio transcription.
{pkgs, ...}: let
  stateDir = "/var/lib/whisper.cpp";
  tmpDir = "${stateDir}/tmp";
in {
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
    "d ${tmpDir} 0750 root root -"
  ];

  systemd.services.whisper-server = {
    description = "whisper.cpp HTTP transcription server for Hermes";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.ffmpeg];
    serviceConfig = {
      ExecStart = "${pkgs.whisper-cpp}/bin/whisper-server -m ${pkgs.whisper-large-v3-turbo} -l zh -t 16 -ng --host 100.65.3.254 --port 8080 --convert --tmp-dir ${tmpDir}";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "10min";
      TimeoutStopSec = "30s";
      WorkingDirectory = stateDir;
    };
  };
}
