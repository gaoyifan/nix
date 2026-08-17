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
    blog = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/blog];
    cjia = mkNixosHost "aarch64-linux" [../nixos/hosts/cjia];
    do = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/do];
    el = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el];
    el2 = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el2];
    el2-install = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el2 ../nixos/hosts/el2/install.nix];
    google = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/google];
    misc0-jp = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/misc0-jp];
    oracle = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/oracle];
    nanopi-r4s-bootstrap = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ({lib, ...}: {
          nixpkgs = {
            overlays = [overlay];
            config.allowUnfreePredicate = package:
              lib.getName package == "arm-trusted-firmware-rk3399";
          };
        })
        ../nixos/hosts/nanopi-r4s-bootstrap
      ];
    };
    oracle2 = mkNixosHost "aarch64-linux" [disko.nixosModules.disko ../nixos/hosts/oracle2];
    oracle3 = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/oracle3 ../nixos/hosts/oracle3/services.nix];
    somo-minisforum = mkNixosHost "x86_64-linux" [../nixos/hosts/somo-minisforum];
    somo-nanopi-r4s = mkNixosHost "aarch64-linux" [../nixos/hosts/somo-nanopi-r4s];
    somo-gw = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/somo-gw];
    xtom-hkg = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-hkg];
    xtom-sjc = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-sjc];
    xtom-syd = mkNixosHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-syd];
  };
  mkNixosBootstrap = {host}: let
    diskNames = builtins.attrNames host.config.disko.devices.disk;
    diskName = builtins.head diskNames;
    disk = host.config.disko.devices.disk.${diskName};
    imageName = "${host.config.networking.hostName}-bootstrap";
    bootstrapHost = host.extendModules {
      modules = [
        {
          boot.growPartition = nixpkgs.lib.mkForce true;
          fileSystems."/".autoResize = nixpkgs.lib.mkForce true;
        }
      ];
    };
  in
    if builtins.length diskNames == 1
    then
      if disk.content.type == "table" && disk.content.format == "msdos"
      then
        import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
          config = bootstrapHost.config;
          inherit (host) pkgs;
          inherit (nixpkgs) lib;
          baseName = imageName;
          copyChannel = false;
          diskSize = 6144;
          partitionTableType = "legacy";
        }
      else
        (bootstrapHost.extendModules {
          modules = [
            {
              disko.devices.disk.${diskName} = {
                imageName = nixpkgs.lib.mkForce imageName;
                imageSize = nixpkgs.lib.mkDefault "6G";
              };
            }
          ];
        }).config.system.build.diskoImages
    else throw "mkNixosBootstrap requires exactly one disko disk for ${host.config.networking.hostName}";
in {
  nixosConfigurations = configs;
  lib = {inherit mkNixosBootstrap;};

  deploy.nodes = {
    blog = mkDeployNode "x86_64-linux" "blog.ts.gaof.net" configs.blog;
    cjia = mkDeployNode "aarch64-linux" "cjia.ts.gaof.net" configs.cjia;
    do = mkDeployNode "x86_64-linux" "do.ts.gaof.net" configs.do;
    el = mkDeployNode "x86_64-linux" "el.ts.gaof.net" configs.el;
    el2 = mkDeployNode "x86_64-linux" "el2.ts.gaof.net" configs.el2;
    google = mkDeployNode "x86_64-linux" "google.ts.gaof.net" configs.google;
    misc0-jp = mkDeployNode "x86_64-linux" "misc0-jp.ts.gaof.net" configs.misc0-jp;
    oracle = mkDeployNode "x86_64-linux" "oracle.ts.gaof.net" configs.oracle;
    oracle2 = mkDeployNode "aarch64-linux" "oracle2.ts.gaof.net" configs.oracle2;
    oracle3 = mkDeployNode "x86_64-linux" "oracle3.ts.gaof.net" configs.oracle3;
    somo-minisforum = mkDeployNode "x86_64-linux" "somo-minisforum.ts.gaof.net" configs.somo-minisforum;
    somo-nanopi-r4s = mkDeployNode "aarch64-linux" "somo-nanopi-r4s.ts.gaof.net" configs.somo-nanopi-r4s;
    somo-gw = mkDeployNode "x86_64-linux" "somo-gw.ts.gaof.net" configs.somo-gw;
    xtom-hkg = mkDeployNode "x86_64-linux" "xtom-hkg.ts.gaof.net" configs.xtom-hkg;
    xtom-sjc = mkDeployNode "x86_64-linux" "xtom-sjc.ts.gaof.net" configs.xtom-sjc;
    xtom-syd = mkDeployNode "x86_64-linux" "xtom-syd.ts.gaof.net" configs.xtom-syd;
  };
}
