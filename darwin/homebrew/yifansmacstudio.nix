let
  defaultHomebrew = import ./default.nix;
in
  defaultHomebrew
  // {
    casks =
      defaultHomebrew.casks
      ++ [
        # Keep Flutter scoped to the Mac Studio.
        "flutter"
      ];
  }
