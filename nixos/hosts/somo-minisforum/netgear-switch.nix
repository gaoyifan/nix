{
  config,
  lib,
  pkgs,
  ...
}: let
  switchAddress = "100.65.2.253";
  switchMacAddress = "78:d2:94:3d:29:fe";
  passwordFile = "/run/agenix/netgear-gs108pev3-password";

  vlanConfigTemplate = pkgs.writeText "gs108pev3-vlans.toml.in" ''
    [switches.gs108pev3]
    address = "${switchAddress}"
    password = "$NETGEAR_SWITCH_PASSWORD"
    model = "gs108ev3"

    [switches.gs108pev3.ports]
    1 = { pvid = 652, vlans = ["1N", "652U"] }
    2 = { pvid = 652, vlans = ["1N", "652U"] }
    3 = { pvid = 652, vlans = ["1N", "652U"] }
    4 = { pvid = 652, vlans = ["1N", "652U"] }
    5 = { pvid = 652, vlans = ["1N", "652U"] }
    6 = { pvid = 652, vlans = ["1N", "652U"] }
    7 = { pvid = 654, vlans = ["1N", "654U"] }
    8 = { pvid = 652, vlans = ["1N", "652U", "654T"] }
  '';

  syncVlans = pkgs.writeShellApplication {
    name = "sync-gs108pev3-vlans";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gettext
      pkgs.prosafe-vlan-manager
    ];
    text = ''
      if [[ ! -r ${lib.escapeShellArg passwordFile} ]]; then
        echo "Cannot read ${passwordFile}; run this command as root on somo-minisforum." >&2
        exit 1
      fi

      umask 077
      runtime_dir="$(mktemp -d)"
      trap 'rm -rf "$runtime_dir"' EXIT

      NETGEAR_SWITCH_PASSWORD="$(<${lib.escapeShellArg passwordFile})"
      export NETGEAR_SWITCH_PASSWORD
      # envsubst, rather than the shell, expands this variable.
      # shellcheck disable=SC2016
      envsubst '$NETGEAR_SWITCH_PASSWORD' \
        < ${vlanConfigTemplate} \
        > "$runtime_dir/config.toml"
      unset NETGEAR_SWITCH_PASSWORD

      prosafe-vlan-manager apply \
        --config "$runtime_dir/config.toml"
    '';
  };
in {
  age.secrets.netgear-gs108pev3-password = lib.mkIf config.services.secrets.hasRealFiles {
    file = config.services.secrets.filesDir + "/nixos/somo-minisforum/netgear-gs108pev3-password.age";
  };

  networking.homeRouter.lans.gnet.dhcpServer.hosts = [
    "${switchMacAddress},${switchAddress},gs108pev3,infinite"
  ];

  environment.systemPackages = [syncVlans];
}
