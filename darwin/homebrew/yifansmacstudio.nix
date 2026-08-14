let
  defaultHomebrew = import ./default.nix;
in
  defaultHomebrew
  // {
    casks =
      defaultHomebrew.casks
      ++ [
        "flutter"
        "handbrake-app" # Video transcoder
        "lm-studio" # Local LLM runner
        "orbstack" # Docker/Linux VM alternative
      ];
  }
