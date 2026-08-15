{...}: {
  imports = [./nylon.nix];

  services.nylon = {
    enable = true;
    overlay = {
      ipv4Subnet = "10.250.10.0/24";
      ipv6Subnet = "fd10:250:10::/64";
      nat.enable = false;
    };
    exits.public.label = 100;
  };
}
