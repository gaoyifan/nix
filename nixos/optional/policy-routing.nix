{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.policyRouting;
  types = lib.types;

  priorities = {
    preMain = 50;
    main = 100;
    postMain = 150;
    wltOutlet = 200;
    wanSource = 300;
    defaultOutlet = 900;
  };

  ruleType = types.either types.singleLineStr (types.submodule {
    options.file = lib.mkOption {
      type = types.str;
      description = "Runtime file containing ip-rule arguments.";
    };
  });
  familyOptions = {
    routingPolicyRules = lib.mkOption {
      type = types.attrsOf (types.listOf ruleType);
      default = {};
      description = "Policy rules grouped by semantic or numeric priority.";
    };
  };

  priorityFor = selector:
    if builtins.hasAttr selector priorities
    then priorities.${selector}
    else if builtins.match "^[1-9][0-9]*$" selector != null
    then let
      priority = lib.toInt selector;
    in
      if priority <= 32765
      then priority
      else throw "policy-routing priority ${selector} must be between 1 and 32765"
    else throw "unknown policy-routing priority ${selector}";

  bucketsFor = family:
    lib.sort (a: b: a.priority < b.priority) (
      lib.mapAttrsToList (selector: entries: {
        inherit entries;
        priority = priorityFor selector;
      })
      (lib.filterAttrs (_: entries: entries != []) cfg.${family}.routingPolicyRules)
    );
  prioritiesAreUnique = family:
    lib.allUnique (map (bucket: bucket.priority) (bucketsFor family));

  emit = line: "printf '%s\\n' ${lib.escapeShellArg line}";
  renderEntry = priority: entry:
    if builtins.isString entry
    then emit "rule add pref ${toString priority} ${entry}"
    else ''
      ${lib.getExe pkgs.gnused} -E \
        -e '/^[[:space:]]*$/d' \
        -e '/^[[:space:]]*#/d' \
        -e 's/^[[:space:]]*pref[[:space:]]+[0-9]+[[:space:]]+//' \
        -e 's/^/rule add pref ${toString priority} /' \
        ${lib.escapeShellArg entry.file}
    '';
  renderFamily = family: terminalRules:
    lib.concatStringsSep "\n" (
      lib.concatMap (
        bucket: map (renderEntry bucket.priority) (lib.unique bucket.entries)
      )
      (bucketsFor family)
      ++ map emit terminalRules
    );
in {
  options.networking.policyRouting = {
    enable = lib.mkEnableOption "declarative RPDB policy routing";
    ipv4 = familyOptions;
    ipv6 = familyOptions;
  };

  config = lib.mkIf cfg.enable {
    networking.policyRouting = {
      ipv4.routingPolicyRules.main = lib.mkDefault ["lookup main suppress_prefixlength 0"];
      ipv6.routingPolicyRules.main = lib.mkDefault ["lookup main suppress_prefixlength 0"];
    };

    assertions = [
      {
        assertion = prioritiesAreUnique "ipv4";
        message = "IPv4 policy-routing selectors must resolve to unique priorities.";
      }
      {
        assertion = prioritiesAreUnique "ipv6";
        message = "IPv6 policy-routing selectors must resolve to unique priorities.";
      }
    ];

    # Keep one declarative desired state for the whole RPDB. Some required rule
    # forms and runtime-generated fragments cannot be represented by networkd,
    # so splitting static rules into .network files would leave two competing
    # owners and make reconciliation less predictable.
    systemd.network.config.networkConfig.ManageForeignRoutingPolicyRules = false;

    systemd.services.policy-routing = {
      description = "Declarative RPDB policy routing";
      wantedBy = ["multi-user.target"];
      wants = ["systemd-networkd.service"];
      after = [
        "systemd-networkd.service"
        "tailscaled.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        {
          echo 'rule flush'
          ${renderFamily "ipv4" [
          "rule add pref 32766 lookup main"
          "rule add pref 32767 lookup default"
        ]}
        } | ${lib.getExe' pkgs.iproute2 "ip"} -4 -force -batch -

        {
          echo 'rule flush'
          ${renderFamily "ipv6" ["rule add pref 32766 lookup main"]}
        } | ${lib.getExe' pkgs.iproute2 "ip"} -6 -force -batch -
      '';
    };
  };
}
