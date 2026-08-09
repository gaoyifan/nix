{
  inputs,
  username,
  mkHomeManagerBackupCommand,
  nixpkgs,
  overlay,
  home-manager,
  deploy-rs,
  disko,
  ...
}: let
  mkNixosHost = system: hostModules:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs username mkHomeManagerBackupCommand;};
      modules =
        [
          {
            nixpkgs.overlays = [overlay];
            nixpkgs.config.allowUnfree = true;
          }
          ../nixos/common
          home-manager.nixosModules.home-manager
        ]
        ++ hostModules;
    };
  mkDeployNode = system: hostname: nixosConfig: {
    inherit hostname;
    sshUser = "root";
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.${system}.activate.nixos nixosConfig;
      remoteBuild = false;
    };
  };
  configs = {
    el = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el];
    el2 = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el2];
    el2-install = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el2 ../nixos/hosts/el2/install.nix];
    misc0-jp = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/misc0-jp];
    oracle2 = mkNixosHost "aarch64-linux" [disko.nixosModules.disko ../nixos/hosts/oracle2];
    somo-minisforum = mkNixosHost "x86_64-linux" [../nixos/hosts/somo-minisforum];
    somo-nanopi-r4s = mkNixosHost "aarch64-linux" [../nixos/hosts/somo-nanopi-r4s];
    somo-gw = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/somo-gw];
    xtom-hkg = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-hkg];
    xtom-sjc = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-sjc];
    xtom-syd = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-syd];
  };
in {
  nixosConfigurations = configs;

  deploy.nodes = {
    el = mkDeployNode "x86_64-linux" "el.ts.gaof.net" configs.el;
    el2 = mkDeployNode "x86_64-linux" "el2.ts.gaof.net" configs.el2;
    misc0-jp = mkDeployNode "x86_64-linux" "misc0-jp.ts.gaof.net" configs.misc0-jp;
    oracle2 = mkDeployNode "aarch64-linux" "oracle2.ts.gaof.net" configs.oracle2;
    somo-minisforum = mkDeployNode "x86_64-linux" "somo-minisforum.ts.gaof.net" configs.somo-minisforum;
    somo-nanopi-r4s = mkDeployNode "aarch64-linux" "somo-nanopi-r4s.ts.gaof.net" configs.somo-nanopi-r4s;
    somo-gw = mkDeployNode "x86_64-linux" "somo-gw.ts.gaof.net" configs.somo-gw;
    xtom-hkg = mkDeployNode "x86_64-linux" "xtom-hkg.ts.gaof.net" configs.xtom-hkg;
    xtom-sjc = mkDeployNode "x86_64-linux" "xtom-sjc.ts.gaof.net" configs.xtom-sjc;
    xtom-syd = mkDeployNode "x86_64-linux" "xtom-syd.ts.gaof.net" configs.xtom-syd;
  };
}
