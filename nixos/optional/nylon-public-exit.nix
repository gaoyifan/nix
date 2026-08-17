{...}: {
  imports = [./nylon.nix];

  services.nylon = {
    enable = true;
    overlay.nat.enable = false;
    exits.public.label = 100;
  };
}
