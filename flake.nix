{
  description = "Nix configuration for yifan";

  # The official cache remains Nix's default. The personal cache intentionally
  # stores only missing paths, so keep it as a lower-priority fallback.
  nixConfig = {
    extra-substituters = [
      "https://nix-cache.yfgao.net?priority=50"
    ];
    extra-trusted-public-keys = [
      "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
    ];
  };

  inputs = {
    # Use 26.05 release branches instead of unstable inputs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";
    systems.url = "github:nix-systems/default";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    userborn = {
      url = "github:jfroche/userborn/system-manager";
      inputs.flake-compat.follows = "flake-compat";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    auto-pause-cemu = {
      url = "github:gaoyifan/auto-pause-cemu";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    witr = {
      url = "github:pranshuparmar/witr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # China IP lists for the wlt outlet selector's nftables CN/overseas
    # destination split (same sources as el2): chnroutes2 for IPv4,
    # china-operator-ip (ip-lists branch) for IPv6.
    chnroutes2 = {
      url = "github:misakaio/chnroutes2";
      flake = false;
    };
    china-operator-ip = {
      url = "github:gaoyifan/china-operator-ip/ip-lists";
      flake = false;
    };

    # Use fork with fix for Nix 2.33+ show-derivation JSON format
    # See: https://github.com/serokell/deploy-rs/pull/359
    deploy-rs = {
      url = "github:serokell/deploy-rs/pull/359/head";
      # url = "github:szlend/deploy-rs/fix-show-derivation-parsing";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
      inputs.utils.follows = "flake-utils";
    };

    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
      inputs.userborn.follows = "userborn";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.7.20";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lark-cli-src = {
      url = "github:larksuite/cli";
      flake = false;
    };

    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-darwin,
    home-manager,
    nix-darwin,
    deploy-rs,
    system-manager,
    disko,
    ...
  } @ inputs: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    linuxSystems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    forAllLinuxSystems = nixpkgs.lib.genAttrs linuxSystems;
    resticBackupHosts = [
      "CJIA-GW.gaof.net"
      "bitmagnet"
      "blog"
      "debian21"
      "debian41"
      "do"
      "docker"
      "docker22"
      "el2"
      "el2.gaof.net"
      "gw-el"
      "misc0-61"
      "misc0-sz"
      "misc1"
      "nfs"
      "nfs2"
      "oracle"
    ];
    tailscaleUserspaceHosts = [
      "debian20"
      "debian21"
      "debian22"
      "debian23-hermes"
      "debian40"
      "debian41"
      "debian42"
    ];
    systemManagerHosts = nixpkgs.lib.unique (resticBackupHosts ++ tailscaleUserspaceHosts);
    nixpkgsForSystem = system:
      if nixpkgs.lib.hasSuffix "darwin" system
      then nixpkgs-darwin
      else nixpkgs;
    pkgsFor = system:
      import (nixpkgsForSystem system) {
        inherit system;
        config.allowUnfree = true;
      };
    username = import ./username.nix;
    homeManagerBackupExtension = "backup-$(date +%Y%m%d-%H%M%S)";
    mkHomeManagerBackupCommand = pkgs:
      pkgs.writeShellScript "home-manager-backup" ''
        target="$1"
        [ -n "$target" ] && mv "$target" "$target.${homeManagerBackupExtension}"
      '';
    darwinHosts = [
      "Yifans-MacBook-Air-2022"
      "YifansMacStudio"
      "Yans-Mac-mini"
      "openclaw"
      "default"
    ];
    customPackages = pkgs:
      import ./pkgs {inherit pkgs inputs;}
      // {
        nft-geo-sets = import ./pkgs/nft-geo-sets.nix {inherit pkgs inputs;};
      };
    cliApps = import ./cli-apps.nix {lib = nixpkgs.lib;};
    overlay = _final: prev: customPackages prev;
    # NixOS host builder: shared nixpkgs setup, common modules, and
    # home-manager integration. Hosts only list their own modules.
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
            ./nixos/common
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
        remoteBuild = true;
      };
    };
    mkLocalBuildDeployNode = system: hostname: nixosConfig: {
      inherit hostname;
      sshUser = "root";
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.${system}.activate.nixos nixosConfig;
        remoteBuild = false;
      };
    };
    mkLinuxSystemConfig = system: extraModules:
      system-manager.lib.makeSystemConfig {
        overlays = [overlay];
        specialArgs = {inherit username;};
        modules =
          [
            ./system-manager/restic.nix
            ./system-manager/tailscale.nix
            # system-manager imports NixOS nginx without the full NixOS module
            # list. This nixpkgs pin's nginx still references security.dhparams;
            # drop this once the pin has nginx sslDhparam removed or system-manager
            # imports the matching dependency itself.
            "${nixpkgs}/nixos/modules/security/dhparams.nix"
            ({pkgs, ...}: {
              nixpkgs.hostPlatform = system;
              nixpkgs.config.allowUnfree = true;
              environment.systemPackages = [
                pkgs.tsshd
              ];
            })
          ]
          ++ extraModules;
      };
  in {
    # Custom packages: nix build .#lazyssh
    packages = forAllSystems (system: let
      pkgs = pkgsFor system;
    in
      (cliApps.mkPackages {
        inherit pkgs;
        customPackages = customPackages pkgs;
      })
      // nixpkgs.lib.optionalAttrs (!(nixpkgs.lib.hasSuffix "darwin" system)) {
        system-manager = system-manager.packages.${system}.default;
      }
      // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
        somo-nanopi-r4s-image = self.nixosConfigurations.somo-nanopi-r4s.config.system.build.sdImage;
      });

    # On-demand CLI apps used by lazy Home Manager wrappers to keep closures small.
    apps = forAllSystems (system: cliApps.mkApps self.packages.${system});

    # nix fmt
    formatter = forAllSystems (system: (nixpkgsForSystem system).legacyPackages.${system}.alejandra);

    # Overlay to make custom packages available as pkgs.lazyssh
    overlays.default = overlay;

    # nix develop
    devShells = forAllSystems (system: {
      default = import ./shell.nix {
        pkgs = (nixpkgsForSystem system).legacyPackages.${system};
        inherit home-manager nix-darwin deploy-rs;
      };
    });

    # Standalone home-manager for non-darwin systems
    # Usage: home-manager switch --flake .#yifan
    legacyPackages = forAllSystems (system:
      if nixpkgs.lib.hasSuffix "darwin" system
      then {}
      else {
        homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            overlays = [overlay];
            config.allowUnfree = true;
          };
          extraSpecialArgs = {inherit inputs;};
          modules = [
            ./home-manager
            {home.username = username;}
          ];
        };
      });

    # macOS system configuration with integrated home-manager
    # Usage: darwin-rebuild switch --flake .
    darwinConfigurations = nixpkgs.lib.genAttrs darwinHosts (
      hostname:
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit inputs username;
            darwinProfile =
              if hostname == "openclaw"
              then "openclaw"
              else if hostname == "YifansMacStudio"
              then "yifansmacstudio"
              else "default";
          };
          modules =
            [
              # Apply overlay and allow unfree packages
              {
                nixpkgs.hostPlatform = "aarch64-darwin";
                nixpkgs.overlays = [overlay];
                nixpkgs.config.allowUnfree = true;
              }
              ./darwin/configuration.nix
              ./darwin/auto-pause-cemu.nix

              # Integrate home-manager as a darwin module
              home-manager.darwinModules.home-manager
              ({pkgs, ...}: {
                home-manager = {
                  useGlobalPkgs = true; # Use system nixpkgs instead of standalone
                  useUserPackages = true; # Install to /etc/profiles instead of ~/.nix-profile
                  backupCommand = mkHomeManagerBackupCommand pkgs;
                  extraSpecialArgs = {inherit inputs;};
                  users.${username} = import ./home-manager;
                };
              })
            ]
            ++ nixpkgs.lib.optional (hostname == "YifansMacStudio") ./darwin/whisper-server.nix;
        }
    );

    # NixOS configurations
    nixosConfigurations = {
      nix-cache = mkNixosHost "x86_64-linux" [./nixos/hosts/nix-cache];
      misc0-jp = mkNixosHost "x86_64-linux" [
        disko.nixosModules.disko
        ./nixos/hosts/misc0-jp
      ];
      somo-minisforum = mkNixosHost "x86_64-linux" [./nixos/hosts/somo-minisforum];
      somo-nanopi-r4s = mkNixosHost "aarch64-linux" [./nixos/hosts/somo-nanopi-r4s];
      somo-gw = mkNixosHost "x86_64-linux" [
        disko.nixosModules.disko
        ./nixos/hosts/somo-gw
      ];
    };

    # Linux system configuration for non-NixOS hosts.
    # Usage: system-manager switch --flake .
    systemConfigs = forAllLinuxSystems (
      system:
        {
          default = mkLinuxSystemConfig system [];
        }
        // nixpkgs.lib.genAttrs systemManagerHosts (
          host:
            mkLinuxSystemConfig system (
              nixpkgs.lib.optional (builtins.elem host resticBackupHosts) {
                services.resticBackup.enable = true;
              }
              ++ nixpkgs.lib.optional (builtins.elem host tailscaleUserspaceHosts) {
                services.tailscale.interfaceName = "userspace-networking";
              }
            )
        )
    );

    # deploy-rs configuration
    deploy.nodes.nix-cache = mkLocalBuildDeployNode "x86_64-linux" "100.64.1.25" self.nixosConfigurations.nix-cache;
    deploy.nodes.misc0-jp = mkDeployNode "x86_64-linux" "103.90.136.69" self.nixosConfigurations.misc0-jp;
    deploy.nodes.somo-minisforum = mkDeployNode "x86_64-linux" "somo-minisforum.ts.gaof.net" self.nixosConfigurations.somo-minisforum;
    deploy.nodes.somo-nanopi-r4s =
      (mkLocalBuildDeployNode "aarch64-linux" "somo-nanopi-r4s.ts.gaof.net" self.nixosConfigurations.somo-nanopi-r4s)
      // {sshOpts = ["-4" "-o" "StrictHostKeyChecking=accept-new"];};
    deploy.nodes.somo-gw = mkLocalBuildDeployNode "x86_64-linux" "115.29.195.35" self.nixosConfigurations.somo-gw;
    checks = let
      # Hermes currently reads package manifests from lib.fileset.toSource
      # results during evaluation. `nix flake check --no-build` uses a
      # read-only store, so these computed source paths are not materialized;
      # deployChecks then forces this host's profile and fails with "path is
      # not valid" on a cold or garbage-collected store. This source filtering
      # was introduced by https://github.com/NousResearch/hermes-agent/pull/65237.
      #
      # Replace only the path seen by deploy-rs checks. The real self.deploy
      # output still contains the NixOS activation path used for deployments.
      # Remove this workaround once Hermes no longer reads filtered sources
      # during evaluation.
      node = self.deploy.nodes.somo-minisforum;
      deployForChecks = self.deploy // {
        nodes = self.deploy.nodes // {
          somo-minisforum = node // {
            profiles = node.profiles // {
              system = node.profiles.system // {
                path = deploy-rs.lib.x86_64-linux.activate.noop (pkgsFor "x86_64-linux").emptyDirectory;
              };
            };
          };
        };
      };
    in
      builtins.mapAttrs (_system: deployLib: deployLib.deployChecks deployForChecks) deploy-rs.lib;
  };
}
