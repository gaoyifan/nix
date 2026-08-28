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
  sharedModules = [
    {
      nixpkgs.overlays = [overlay];
      nixpkgs.config.allowUnfree = true;
    }
    ../nixos/common
    ../nixos/nylon/fleet.nix
    home-manager.nixosModules.home-manager
  ];
  mkDeployableHost = system: modules: {
    inherit system modules;
    deploy = true;
  };
  mkNixosOnlyHost = system: modules: {
    inherit system modules;
    deploy = false;
  };
  mkNixosHost = name: host:
    nixpkgs.lib.nixosSystem {
      inherit (host) system;
      specialArgs = {
        inherit
          inputs
          username
          mkHomeManagerBackupCommand
          nylonTopology
          ;
        nixosConfigurationName = name;
      };
      modules = sharedModules ++ host.modules;
    };
  mkDeployNode = name: host: {
    hostname = "${name}.ts.gaof.net";
    sshUser = "root";
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.${host.system}.activate.nixos configs.${name};
      remoteBuild = false;
    };
  };
  hostInventory = {
    ali-sg = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/ali-sg];
    blog = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/blog];
    cjia = mkDeployableHost "aarch64-linux" [../nixos/hosts/cjia];
    do = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/do];
    el = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el];
    el2 = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el2];
    el2-install = mkNixosOnlyHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/el2 ../nixos/hosts/el2/install.nix];
    google = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/google];
    misc0-jp = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/misc0-jp];
    misc1-sz = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/misc1-sz];
    misc1-sh = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/misc1-sh];
    nfs = mkDeployableHost "x86_64-linux" [../nixos/hosts/nfs];
    nixos-orbstack = mkDeployableHost "aarch64-linux" [../nixos/hosts/nixos-orbstack];
    oracle = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/oracle];
    oracle2 = mkDeployableHost "aarch64-linux" [disko.nixosModules.disko ../nixos/hosts/oracle2];
    oracle3 = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/oracle3 ../nixos/hosts/oracle3/services.nix];
    somo-minisforum = mkDeployableHost "x86_64-linux" [../nixos/hosts/somo-minisforum];
    somo-nanopi-r4s = mkDeployableHost "aarch64-linux" [../nixos/hosts/somo-nanopi-r4s];
    somo-gw = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/somo-gw];
    xtom-hkg = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-hkg];
    xtom-sjc = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-sjc];
    xtom-syd = mkDeployableHost "x86_64-linux" [disko.nixosModules.disko ../nixos/hosts/xtom-syd];
  };
  deployableHostNames = nixpkgs.lib.attrNames (nixpkgs.lib.filterAttrs (_: host: host.deploy) hostInventory);
  nylonTopology = import ../nixos/nylon/compile.nix {
    lib = nixpkgs.lib;
    mesh = import ../nixos/nylon/mesh.nix;
    nodes = import ../nixos/nylon/nodes;
    deployableHosts = deployableHostNames;
  };
  configs =
    nixpkgs.lib.mapAttrs mkNixosHost hostInventory
    // {
      # The universal bootstrap image is not a deployable host and intentionally
      # omits shared modules.
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
    };
  mkNixosDiskImage = {host}: let
    diskNames = builtins.attrNames (host.config.disko.devices.disk or {});
    diskName = builtins.head diskNames;
    disk = host.config.disko.devices.disk.${diskName};
    imageName = "${host.config.networking.hostName}-disk-image";
    imageHost = host.extendModules {
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
          config = imageHost.config;
          inherit (host) pkgs;
          inherit (nixpkgs) lib;
          baseName = imageName;
          copyChannel = false;
          diskSize = 6144;
          partitionTableType = "legacy";
        }
      else
        (imageHost.extendModules {
          modules = [
            {
              disko.devices.disk.${diskName} = {
                imageName = nixpkgs.lib.mkForce imageName;
                imageSize = nixpkgs.lib.mkDefault "6G";
              };
            }
          ];
        }).config.system.build.diskoImages
    else throw "mkNixosDiskImage requires exactly one disko disk for ${host.config.networking.hostName}";
in {
  nixosConfigurations = nixpkgs.lib.mapAttrs (_: host:
    host
    // {
      diskImage = mkNixosDiskImage {inherit host;};
    })
  configs;
  lib = {
    inherit mkNixosDiskImage;
    nylonManifest = nylonTopology.manifest;
  };

  deploy.nodes = nixpkgs.lib.mapAttrs mkDeployNode (
    nixpkgs.lib.filterAttrs (_: host: host.deploy) hostInventory
  );
}
