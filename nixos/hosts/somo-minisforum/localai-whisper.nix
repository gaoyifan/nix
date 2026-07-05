# LocalAI OpenAI-compatible Whisper API backed by the official Vulkan image.
{
  lib,
  pkgs,
  ...
}: let
  stateDir = "/var/lib/localai";
  modelsDir = "${stateDir}/models";
  backendsDir = "${stateDir}/backends";
  dataDir = "${stateDir}/data";
  uploadsDir = "${stateDir}/uploads";

  whisperModelConfig = pkgs.writeText "localai-whisper-1.yaml" ''
    name: whisper-1
    backend: whisper
    parameters:
      model: ggml-large-v3.bin

    download_files:
    - filename: ggml-large-v3.bin
      uri: https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin
  '';
in {
  virtualisation.oci-containers.containers.localai-whisper = {
    image = "docker.io/localai/localai:latest-gpu-vulkan";
    volumes = [
      "${modelsDir}:/models"
      "${backendsDir}:/backends"
      "${dataDir}:/data"
      "${uploadsDir}:/tmp/localai/upload"
      "${whisperModelConfig}:/models/whisper-1.yaml:ro"
    ];
    environment = {
      LOCALAI_ADDRESS = "127.0.0.1:8080";
      LOCALAI_MODELS_PATH = "/models";
      LOCALAI_BACKENDS_PATH = "/backends";
      LOCALAI_UPLOAD_PATH = "/tmp/localai/upload";
      LOCALAI_UPLOAD_LIMIT = "200";
      LOCALAI_THREADS = "16";
      LOCALAI_SINGLE_ACTIVE_BACKEND = "true";
      LOCALAI_DISABLE_WEBUI = "true";
      MODELS_PATH = "/models";
    };
    extraOptions = [
      "--network=host"
      "--device=/dev/dri"
      "--group-add=26"
      "--group-add=303"
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
    "d ${modelsDir} 0750 root root -"
    "d ${backendsDir} 0750 root root -"
    "d ${dataDir} 0750 root root -"
    "d ${uploadsDir} 0750 root root -"
  ];

  systemd.services.podman-localai-whisper.serviceConfig.ExecStartPre = lib.mkAfter [
    (pkgs.writeShellScript "localai-whisper-install-backend" ''
      set -euo pipefail

      if [ -x ${backendsDir}/vulkan-whisper/run.sh ]; then
        exit 0
      fi

      ${pkgs.podman}/bin/podman pull docker.io/localai/localai:latest-gpu-vulkan
      ${pkgs.podman}/bin/podman run --rm \
        --name localai-whisper-backend-install \
        --entrypoint=/local-ai \
        -e LOCALAI_BACKENDS_PATH=/backends \
        -v ${backendsDir}:/backends \
        docker.io/localai/localai:latest-gpu-vulkan \
        backends install localai@vulkan-whisper
    '')
  ];
}
