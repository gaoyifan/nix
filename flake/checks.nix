{
  self,
  inputs,
  nixpkgs,
  pkgsFor,
  overlay,
  deploy-rs,
  ...
}: {
  checks = let
    # Hermes reads filtered package sources during evaluation, but
    # `nix flake check --no-build` cannot materialize them in a read-only store.
    # Keep the real deployment path intact and replace only the check profile.
    deployForChecks =
      nixpkgs.lib.updateManyAttrsByPath [
        {
          path = ["nodes" "somo-minisforum" "profiles" "system" "path"];
          update = _: deploy-rs.lib.x86_64-linux.activate.noop (pkgsFor "x86_64-linux").emptyDirectory;
        }
      ]
      self.deploy;
    deployChecks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks deployForChecks) deploy-rs.lib;
    x86Pkgs = (pkgsFor "x86_64-linux").extend overlay;
    lowMemoryGptHost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [inputs.disko.nixosModules.disko ../nixos/tests/low-memory-gpt-host.nix];
    };
    nylonFixture = import ../nixos/nylon/tests/fixture.nix {lib = nixpkgs.lib;};
    nylonRuntimeFixture = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs nylonFixture;
      };
      modules = [
        {nixpkgs.pkgs = x86Pkgs;}
        ../nixos/nylon/tests/runtime-module.nix
      ];
    };
    nylonFixtureCentral = x86Pkgs.writeText "nylon-fixture-central.yaml" nylonFixture.selector.central.text;
    nylonFixtureNode = x86Pkgs.writeText "nylon-fixture-node.yaml" nylonFixture.nodeConfigText;
  in
    nixpkgs.lib.recursiveUpdate deployChecks {
      x86_64-linux =
        {
          home-router = x86Pkgs.testers.runNixOSTest (import ../nixos/tests/home-router.nix {inherit inputs;});
          low-memory-disk-image = import ../nixos/tests/low-memory-disk-image.nix {
            inherit (inputs) disko;
            hostConfig = lowMemoryGptHost;
            inherit (self.lib) mkNixosDiskImage;
            inherit nixpkgs;
            pkgs = x86Pkgs;
          };
          nixos-disk-writer-kexec = import ../nixos/tests/nixos-disk-writer-kexec.nix {
            hostConfig = lowMemoryGptHost;
            kexecInstallerTarball = self.packages.x86_64-linux.nixos-disk-writer-kexec;
            inherit (self.lib) mkNixosDiskImage;
            pkgs = x86Pkgs;
          };
          nylon-health-runner = self.packages.x86_64-linux.nylon-health-runner;
          nylon-powerdns-reconcile = self.packages.x86_64-linux.nylon-powerdns-reconcile;
          nylon-config-parser = x86Pkgs.runCommand "nylon-config-parser-check" {} ''
            test "$(printf '%s\n' ${nixpkgs.lib.escapeShellArg nylonFixture.privateKey} \
              | ${nixpkgs.lib.getExe x86Pkgs.nylon} pubkey)" = \
              ${nixpkgs.lib.escapeShellArg nylonFixture.publicKey}
            ${nixpkgs.lib.getExe x86Pkgs.nylon} verify ${nylonFixtureCentral}
            ${nixpkgs.lib.getExe x86Pkgs.nylon} verify ${nylonFixtureCentral} --node ${nylonFixtureNode}
            touch "$out"
          '';
          nylon-runtime-module = let
            config = nylonRuntimeFixture.config;
            selector = config.services.nylon.compiled.selector;
            nylonService = config.systemd.services.nylon;
            centralSource = config.environment.etc."nylon/central.yaml".source;
            publicNodeSource = config.environment.etc."nylon/node-public.yaml".source;
            scriptLines = nixpkgs.lib.splitString "\n" config.systemd.services.nylon-routes.script;
            routeCommands4 = builtins.filter (nixpkgs.lib.hasPrefix "ip -4 route replace ") scriptLines;
            routeCommands6 = builtins.filter (nixpkgs.lib.hasPrefix "ip -6 route replace ") scriptLines;
          in
            assert config.services.nylon.udpPort == config.services.nylon.compiled.publicNode.value.port;
            assert builtins.elem centralSource nylonService.restartTriggers;
            assert builtins.elem publicNodeSource nylonService.restartTriggers;
            assert nylonService.reloadTriggers == [];
            assert builtins.hasAttr "ExecReload" nylonService.serviceConfig;
            assert builtins.length selector.routes.ipv4 == 1;
            assert builtins.length selector.routes.ipv6 == 1;
            assert routeCommands4 == builtins.map (route: "ip -4 ${route}") selector.routes.ipv4;
            assert routeCommands6 == builtins.map (route: "ip -6 ${route}") selector.routes.ipv6;
              x86Pkgs.writeText "nylon-runtime-module-check.json" (builtins.toJSON {
                fixtureHost = config.networking.hostName;
                ipv4RouteCommands = builtins.length routeCommands4;
                ipv6RouteCommands = builtins.length routeCommands6;
                restartTriggers = builtins.length nylonService.restartTriggers;
              });
          nylon-wlt-parser = let
            groups = (builtins.fromTOML nylonFixture.selector.selector.wlt.text).outlet_groups;
            outletName = "ZZ Fixture | Test";
          in
            assert builtins.map (group: group.title) groups == ["国内出口" "海外出口"];
            assert (builtins.elemAt groups 0).outlets == {${outletName} = 1507328;};
            assert (builtins.elemAt groups 0).outlets_v6 == {${outletName} = 1507328;};
            assert (builtins.elemAt groups 1).outlets == {${outletName} = 368;};
            assert (builtins.elemAt groups 1).outlets_v6 == {${outletName} = 368;};
              x86Pkgs.writeText "nylon-wlt-parser-check.json" (builtins.toJSON {
                outletGroups = builtins.length groups;
                inherit outletName;
              });
          nylon-topology = x86Pkgs.writeText "nylon-topology-check.json" (
            builtins.toJSON (import ../nixos/nylon/tests/topology.nix {lib = nixpkgs.lib;})
          );
          oob-ssh = x86Pkgs.testers.runNixOSTest (import ../nixos/tests/oob-ssh.nix {pkgs = x86Pkgs;});
        }
        // nixpkgs.lib.optionalAttrs (builtins.pathExists ../secrets/files/.gitkeep) {
          nylon-production-secrets = let
            filesDir = ../secrets/files;
            summary = import ../nixos/nylon/check-secrets.nix {
              inherit filesDir;
              nodes = import ../nixos/nylon/nodes;
              powerDnsController = (import ../nixos/nylon/mesh.nix).dns.controller;
              recipientRules = import (filesDir + "/secrets.nix");
            };
          in
            x86Pkgs.writeText "nylon-production-secrets-check.json" (builtins.toJSON summary);
        };
    };
}
