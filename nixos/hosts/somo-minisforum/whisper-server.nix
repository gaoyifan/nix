# whisper.cpp HTTP server for Hermes audio transcription.
{
  imports = [../../optional/whisper-server.nix];

  services.whisper-server = {
    enable = true;
    listenAddress = "100.65.3.254";
  };

  systemd.services.whisper-server.description = "whisper.cpp HTTP transcription server for Hermes";
}
