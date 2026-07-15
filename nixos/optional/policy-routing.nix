{
  config,
  lib,
  pkgs,
  ...
}: let
  types = lib.types;
  cfg = config.networking.policyRouting;

  mkRulesFile = family: rules:
    pkgs.writeText "policy-routing-${family}-rules.batch" ''
      ${lib.concatMapStringsSep "\n" (rule: "rule add ${rule}") rules}
    '';

  mkAppendRuleFiles = files:
    lib.concatMapStringsSep "\n" (
      file: ''
        sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' -e 's/^/rule add /' ${lib.escapeShellArg file}
      ''
    )
    files;
in {
  options.networking.policyRouting = {
    enable = lib.mkEnableOption "declarative RPDB policy routing";

    ipv4 = {
      rules = lib.mkOption {
        type = types.listOf types.singleLineStr;
        default = [
          "pref 32766 lookup main"
          "pref 32767 lookup default"
        ];
        description = "IPv4 rules as ip-rule arguments, one rule per entry; omit the rule add prefix.";
      };

      ruleFiles = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        description = "External IPv4 rule fragments; each non-empty, non-comment line is appended after rule add.";
      };
    };

    ipv6 = {
      rules = lib.mkOption {
        type = types.listOf types.singleLineStr;
        default = [
          "pref 32766 lookup main"
        ];
        description = "IPv6 rules as ip-rule arguments, one rule per entry; omit the rule add prefix.";
      };

      ruleFiles = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        description = "External IPv6 rule fragments; each non-empty, non-comment line is appended after rule add.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.policy-routing = let
      ipv4Rules = mkRulesFile "ipv4" cfg.ipv4.rules;
      ipv6Rules = mkRulesFile "ipv6" cfg.ipv6.rules;
    in {
      description = "Declarative RPDB policy routing";
      wantedBy = ["multi-user.target"];
      wants = ["systemd-networkd.service"];
      after = [
        "systemd-networkd.service"
        "tailscaled.service"
      ];
      path = [
        pkgs.coreutils
        pkgs.gnused
        pkgs.iproute2
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        {
          echo 'rule flush'
          cat ${ipv4Rules}
          ${mkAppendRuleFiles cfg.ipv4.ruleFiles}
        } | ip -4 -force -batch -

        {
          echo 'rule flush'
          cat ${ipv6Rules}
          ${mkAppendRuleFiles cfg.ipv6.ruleFiles}
        } | ip -6 -force -batch -
      '';
    };
  };
}
