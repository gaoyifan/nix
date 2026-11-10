{
  imports = [../../../optional/whisper-server.nix];

  services.whisper-server = {
    enable = true;
    listenAddress = "100.64.2.254";
    port = 8178;
  };

  systemd.services.whisper-server = {
    description = "Whisper audio transcription fallback for Rakazo";
    serviceConfig.DynamicUser = true;
  };
}
