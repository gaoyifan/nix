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
  modelPath = "${modelsDir}/${modelName}";
  modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${modelName}";
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
      pkgs.curl
      pkgs.ffmpeg
      pkgs.whisper-cpp
    ];
    preStart = ''
      set -euo pipefail

      mkdir -p ${lib.escapeShellArg modelsDir} ${lib.escapeShellArg tmpDir}

      if [ ! -s ${lib.escapeShellArg modelPath} ]; then
        if [ -s /tmp/whisper-models/${lib.escapeShellArg modelName} ]; then
          install -m 0644 /tmp/whisper-models/${lib.escapeShellArg modelName} ${lib.escapeShellArg modelPath}
        else
          tmp_model=${lib.escapeShellArg modelPath}.tmp
          curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 \
            -o "$tmp_model" \
            ${lib.escapeShellArg modelUrl}
          chmod 0644 "$tmp_model"
          mv "$tmp_model" ${lib.escapeShellArg modelPath}
        fi
      fi

      if [ -s /var/lib/localai/models/ggml-large-v3.bin ] && [ ! -e ${lib.escapeShellArg modelsDir}/ggml-large-v3.bin ]; then
        ln -s /var/lib/localai/models/ggml-large-v3.bin ${lib.escapeShellArg modelsDir}/ggml-large-v3.bin
      fi
    '';
    serviceConfig = {
      ExecStart = "${pkgs.whisper-cpp}/bin/whisper-server -m ${lib.escapeShellArg modelPath} -l zh -t 16 -ng --host 100.65.3.254 --port 8080 --convert --tmp-dir ${lib.escapeShellArg tmpDir}";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "10min";
      TimeoutStopSec = "30s";
      WorkingDirectory = stateDir;
    };
  };
}
