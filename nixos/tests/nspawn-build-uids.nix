{
  inputs,
  pkgs,
}: let
  build = pkgs.writeText "uid-isolation-build.nix" ''
    { name }: derivation {
      inherit name;
      system = "${pkgs.stdenv.hostPlatform.system}";
      builder = "${pkgs.bash}/bin/bash";
      args = [ "-c" ${builtins.toJSON ''
      if [ "$name" = guest ]; then
        ${pkgs.coreutils}/bin/touch /tmp/guest-started
        while [ ! -e /tmp/release-guest ]; do
          ${pkgs.coreutils}/bin/sleep 0.1
        done
      fi
      printf '%s\n' "$name" "$(${pkgs.coreutils}/bin/id -u)" > "$out"
    ''} ];
    }
  '';
in {
  name = "nspawn-build-uids";

  nodes.machine = {
    imports = [../optional/github-runner/nspawn.nix];
    services.github-runner-nspawn.runner = {
      root = "/var/lib/runner";
      tokenFile = "/etc/runner-token";
      buildUsersUidBase = 40000;
      nspawnArgs = [];
      guestModule = {
        boot.isContainer = true;
        networking.hostName = "runner";
        nixpkgs.flake = {
          setNixPath = false;
          setFlakeRegistry = false;
        };
        nix.nrBuildUsers = 1;
        nix.settings.sandbox = false;
        environment.etc."build.nix".source = build;
        system.stateVersion = "26.05";
      };
    };
    _module.args.inputs = inputs;
    nix.nrBuildUsers = 1;
    nix.settings = {
      experimental-features = ["nix-command"];
      sandbox = false;
    };
    environment.etc."build.nix".source = build;
    environment.etc.runner-token.text = "test";
    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
  };

  testScript = ''
    import shlex

    machine.wait_for_unit("runner.service")

    def guest(command):
        return "systemd-run --quiet --machine=runner --wait --pipe /bin/sh -lc " + shlex.quote(command)

    machine.wait_until_succeeds(guest("test -e /run/current-system"))
    host_uid = machine.succeed("id -u nixbld1").strip()
    guest_uid = machine.succeed(guest("id -u nixbld40001")).strip()
    assert host_uid != guest_uid, (host_uid, guest_uid)

    # Seed the old declared account and NixOS ownership tracking.
    machine.succeed(guest(f"usermod --login nixbld1 --uid {host_uid} nixbld40001"))
    machine.succeed(guest("sed -i s/nixbld40001/nixbld1/g /var/lib/nixos/declarative-users"))
    assert machine.succeed(guest("id -u nixbld1")).strip() == host_uid

    # A registered output predating the concurrent builds must retain ownership.
    existing = machine.succeed(guest("NIX_REMOTE=local nix-build /etc/build.nix --argstr name existing --no-out-link")).strip()
    ownership = machine.succeed(guest(f"stat -c '%u:%g:%a' {existing}")).strip()
    assert ownership.startswith("0:"), ownership
    store_ownership = machine.succeed(guest("stat -c '%u:%g:%a' /nix/store")).strip()
    assert store_ownership == "0:30000:1775", store_ownership

    machine.succeed("systemctl restart runner.service")
    machine.wait_until_succeeds(guest("test -e /run/current-system"))
    migrated_uid = machine.succeed(guest("id -u nixbld40001")).strip()
    assert migrated_uid == guest_uid, (migrated_uid, guest_uid)
    machine.fail(guest("getent passwd nixbld1"))
    members = machine.succeed(guest("getent group nixbld")).strip().split(":")[3]
    assert members == "nixbld40001", members

    machine.succeed("systemd-run --unit=guest-build " + guest("NIX_REMOTE=local nix-build /etc/build.nix --argstr name guest --out-link /tmp/guest-result"))
    machine.wait_until_succeeds(guest("test -e /tmp/guest-started"))
    host_output = machine.succeed("NIX_REMOTE=local nix-build /etc/build.nix --argstr name host --no-out-link").strip()
    assert machine.succeed(f"cat {host_output}").splitlines() == ["host", host_uid]
    machine.succeed(guest("touch /tmp/release-guest"))
    machine.wait_until_succeeds(guest("test -e /tmp/guest-result"))
    assert machine.succeed(guest("cat /tmp/guest-result")).splitlines() == ["guest", guest_uid]

    machine.succeed(guest(f"nix-store --verify-path {existing}"))
    assert machine.succeed(guest(f"stat -c '%u:%g:%a' {existing}")).strip() == ownership
    assert machine.succeed(guest("stat -c '%u:%g:%a' /nix/store")).strip() == store_ownership
  '';
}
