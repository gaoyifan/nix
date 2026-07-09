# whisper.cpp HTTP server for Hermes audio transcription.
{
  lib,
  pkgs,
  ...
}: let
  stateDir = "/var/lib/whisper.cpp";
  modelsDir = "${stateDir}/models";
  tmpDir = "${stateDir}/tmp";
  modelName = "ggml-large-v3-turbo.bin";
  model = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${modelName}";
    hash = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
  };
in {
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
    "d ${modelsDir} 0750 root root -"
    "d ${tmpDir} 0750 root root -"
  ];

  systemd.services.whisper-server = {
    description = "whisper.cpp HTTP transcription server for Hermes";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    path = [
      pkgs.coreutils
      pkgs.ffmpeg
      pkgs.whisper-cpp
    ];
    preStart = ''
      set -euo pipefail

      if [ -s /var/lib/localai/models/ggml-large-v3.bin ] && [ ! -e ${lib.escapeShellArg modelsDir}/ggml-large-v3.bin ]; then
        ln -s /var/lib/localai/models/ggml-large-v3.bin ${lib.escapeShellArg modelsDir}/ggml-large-v3.bin
      fi
    '';
    serviceConfig = {
      ExecStart = "${pkgs.whisper-cpp}/bin/whisper-server -m ${model} -l zh -t 16 -ng --host 100.65.3.254 --port 8080 --convert --tmp-dir ${lib.escapeShellArg tmpDir}";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "10min";
      TimeoutStopSec = "30s";
      WorkingDirectory = stateDir;
    };
  };
}
