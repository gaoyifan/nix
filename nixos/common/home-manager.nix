# Home Manager integration shared by all NixOS hosts.
{
  inputs,
  mkHomeManagerBackupCommand,
  pkgs,
  username,
  ...
}: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupCommand = mkHomeManagerBackupCommand pkgs;
    extraSpecialArgs = {inherit inputs;};
    users.${username} = {pkgs, ...}: {
      imports = [../../home-manager];
      home.packages = [inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default];
    };
  };
}
