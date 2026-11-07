{
  inputs,
  username,
  mkHomeManagerBackupCommand,
  nixpkgs,
  overlay,
  home-manager,
  deploy-rs,
  disko,
  forAllLinuxSystems,
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
    disko.nixosModules.disko
  ];
  mkHost = system: modules: {inherit system modules;};
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
  mkNanopiImageHost = module: specialArgs:
    nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      inherit specialArgs;
      modules = [
        {
          nixpkgs.overlays = [overlay];
          nixpkgs.config.allowUnfree = true;
        }
        module
      ];
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
    ali-sg = mkHost "x86_64-linux" [../nixos/hosts/ali-sg];
    baihualin = mkHost "aarch64-linux" [../nixos/hosts/baihualin];
    blog = mkHost "x86_64-linux" [../nixos/hosts/blog];
    cjia = mkHost "aarch64-linux" [../nixos/hosts/cjia];
    el = mkHost "x86_64-linux" [../nixos/hosts/el];
    el2 = mkHost "x86_64-linux" [../nixos/hosts/el2];
    google = mkHost "x86_64-linux" [../nixos/hosts/google];
    hhost-jp = mkHost "x86_64-linux" [../nixos/hosts/hhost-jp];
    misc0-jp = mkHost "x86_64-linux" [../nixos/hosts/misc0-jp];
    misc1-sz = mkHost "x86_64-linux" [../nixos/hosts/misc1-sz];
    misc1-sh = mkHost "x86_64-linux" [../nixos/hosts/misc1-sh];
    nfs = mkHost "x86_64-linux" [../nixos/hosts/nfs];
    nixos-orbstack = mkHost "aarch64-linux" [../nixos/hosts/nixos-orbstack];
    oracle = mkHost "x86_64-linux" [../nixos/hosts/oracle];
    oracle2 = mkHost "aarch64-linux" [../nixos/hosts/oracle2];
    oracle3 = mkHost "x86_64-linux" [../nixos/hosts/oracle3 ../nixos/hosts/oracle3/services.nix];
    somo-minisforum = mkHost "x86_64-linux" [../nixos/hosts/somo-minisforum];
    somo-nanopi-r4s = mkHost "aarch64-linux" [../nixos/hosts/somo-nanopi-r4s];
    somo-gw = mkHost "x86_64-linux" [../nixos/hosts/somo-gw];
    xtom-hkg = mkHost "x86_64-linux" [../nixos/hosts/xtom-hkg];
    xtom-sjc = mkHost "x86_64-linux" [../nixos/hosts/xtom-sjc];
    xtom-syd = mkHost "x86_64-linux" [../nixos/hosts/xtom-syd];
  };
  deployNodes = nixpkgs.lib.mapAttrs mkDeployNode hostInventory;
  nylonTopology = import ../nixos/nylon/compile.nix {
    lib = nixpkgs.lib;
    mesh = import ../nixos/nylon/mesh.nix;
    nodes = import ../nixos/nylon/nodes;
    deployableHosts = nixpkgs.lib.attrNames hostInventory;
  };
  configs =
    nixpkgs.lib.mapAttrs mkNixosHost hostInventory
    // {
      # The universal bootstrap image is not a deployable host and intentionally
      # omits shared modules.
      nanopi-r4s-bootstrap = mkNanopiImageHost ../nixos/hosts/nanopi-r4s-bootstrap {};
      nanopi-r5c-bootstrap = mkNanopiImageHost ../nixos/hosts/nanopi-r5c-bootstrap {};
      nanopi-r5c-emmc-flasher = mkNanopiImageHost ../nixos/hosts/nanopi-r5c-emmc-flasher {
        bootstrapImage = configs.nanopi-r5c-bootstrap.config.system.build.sdImage;
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
    # Group by inventory metadata without evaluating configurations to discover
    # their platform. CI can then evaluate each profile independently.
    nixosHostProfiles = forAllLinuxSystems (system:
      nixpkgs.lib.mapAttrs (name: _: deployNodes.${name}.profiles.system.path)
      (nixpkgs.lib.filterAttrs (_: host: host.system == system) hostInventory));
  };

  deploy.nodes = deployNodes;
}
