{
  description = "Nix configuration for yifan";

  nixConfig = {
    # Flake configuration must be literal; imported values remain thunks.
    # cache.nixos.org remains Nix's built-in fallback.
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

    wlt = {
      url = "github:gaoyifan/wlt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    loft = {
      url = "github:gaoyifan/loft/a41f84683ec33b88c333b65e877536ec92efa155";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    codex-api = {
      url = "github:gaoyifan/codex-api";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    codex-capacity-proxy = {
      url = "github:gaoyifan/codex-capacity-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    github-backup = {
      url = "github:gaoyifan/github-backup";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    restic-115 = {
      url = "github:gaoyifan/restic-115";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    restic-123pan = {
      url = "github:gaoyifan/restic-123pan";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    restic-sync = {
      url = "github:gaoyifan/restic-sync";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    diverge = {
      url = "github:gaoyifan/diverge-rs";
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

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-images = {
      url = "github:nix-community/nixos-images";
      inputs.nixos-stable.follows = "nixpkgs";
      inputs.nixos-unstable.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.darwin.follows = "nix-darwin";
      inputs.systems.follows = "systems";
    };

    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.8.27";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    herdr = {
      url = "github:herdrdev/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    lark-cli-src = {
      url = "github:larksuite/cli";
      flake = false;
    };

    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };

    open-kimi-ppt-skill = {
      url = "github:gaoyifan/open-kimi-ppt-skill";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-darwin,
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
    customPackages = pkgs: import ./pkgs {inherit pkgs inputs;};
    cliApps = import ./cli-apps.nix {lib = nixpkgs.lib;};
    overlay = _final: prev: customPackages prev;
    treefmtEval = forAllSystems (system: inputs.treefmt-nix.lib.evalModule (pkgsFor system) ./treefmt.nix);
    domainArgs =
      inputs
      // {
        inherit
          inputs
          forAllSystems
          forAllLinuxSystems
          nixpkgsForSystem
          pkgsFor
          username
          mkHomeManagerBackupCommand
          customPackages
          cliApps
          overlay
          treefmtEval
          ;
      };
  in
    nixpkgs.lib.foldl' nixpkgs.lib.recursiveUpdate {} (
      map (path: import path domainArgs) [
        ./flake/packages.nix
        ./flake/formatter.nix
        ./flake/devshell.nix
        ./flake/home-manager.nix
        ./flake/darwin.nix
        ./flake/nixos.nix
        ./flake/system-manager.nix
        ./flake/checks.nix
      ]
    );
}
