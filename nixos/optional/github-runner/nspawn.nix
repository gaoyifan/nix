{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.github-runner-nspawn;
  guests = lib.mapAttrs (_: runner:
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        runner.guestModule
        ({config, ...}: {
          ids.uids.nixbld = lib.mkForce runner.buildUsersUidBase;
          # New names let NixOS replace old declared accounts instead of
          # retaining their UIDs. Registered store ownership stays unchanged.
          users.users =
            lib.genAttrs
            (map (i: "nixbld${toString i}") (lib.range 1 config.nix.nrBuildUsers))
            (name: {name = "nixbld${toString config.users.users.${name}.uid}";});
        })
      ];
    }).config)
  cfg;
  allUids = lib.concatMap (cfg:
    lib.mapAttrsToList (_: user: user.uid) (
      lib.filterAttrs (_: user: user.group == "nixbld") cfg.users.users
    ))
  ([config] ++ builtins.attrValues guests);
in {
  options.services.github-runner-nspawn = lib.mkOption {
    internal = true;
    type = lib.types.attrsOf lib.types.attrs;
    default = {};
    description = "Independent Nix store runners in systemd-nspawn containers.";
  };

  config = {
    assertions = [
      {
        assertion = builtins.length allUids == builtins.length (lib.unique allUids);
        message = "The host and nspawn runners must use disjoint Nix build UIDs.";
      }
    ];

    systemd.services =
      lib.mapAttrs (name: runner: let
        inherit (runner) root tokenFile;
        requires = runner.requires or [];
        runnerToplevel = guests.${name}.system.build.toplevel;
      in {
        inherit requires;
        wantedBy = runner.wantedBy or ["multi-user.target"];
        after = requires ++ ["network-online.target"];
        wants = ["network-online.target"];
        unitConfig.ConditionPathExists = tokenFile;
        path = [config.nix.package];
        preStart = ''
          install -d -m 0755 ${root}
          nix copy --no-check-sigs --to 'local?root=${root}' ${runnerToplevel}
          install -d -m 0755 ${root}/nix/var/nix/profiles
          ln -sfn ${runnerToplevel} ${root}/nix/var/nix/profiles/system
          install -d -m 0755 ${root}/etc ${root}/usr
          if [[ ! -e ${root}/etc/os-release && ! -L ${root}/etc/os-release ]]; then
            touch ${root}/etc/os-release
          fi
        '';
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "all";
          Delegate = true;
          KillMode = "mixed";
          Restart = "on-failure";
          RestartSec = "10s";
          TimeoutStartSec = "15min";
          TimeoutStopSec = "5min";
          ExecStart = lib.concatStringsSep " " (
            [
              "${pkgs.systemd}/bin/systemd-nspawn"
              "--keep-unit --settings=no --machine=${runner.machine or name}"
              "--directory=${root} --notify-ready=yes --kill-signal=SIGRTMIN+3"
            ]
            ++ runner.nspawnArgs
            ++ [
              "--bind-ro=${tokenFile}:/run/github-runner-token"
              "${runnerToplevel}/init"
            ]
          );
        };
      })
      cfg;
  };
}
