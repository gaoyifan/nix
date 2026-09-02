{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.age;
  templatesDir = "/run/agenix-templates";
  generationsDir = "${templatesDir}.d";
  placeholder = name: "__AGENIX_${builtins.hashString "sha256" name}__";
  placeholders = lib.mapAttrs (name: _: placeholder name) cfg.secrets;
  renderTemplate = name: template: let
    target = "$new_generation/${lib.escapeShellArg name}";
    usedSecrets = lib.filter (secret: lib.hasInfix placeholders.${secret} template.content) (lib.attrNames cfg.secrets);
  in ''
    target=${target}
    install -m 0400 ${pkgs.writeText "agenix-template-${name}" template.content} "$target"
    ${lib.concatMapStringsSep "\n" (secret: ''
        ${lib.getExe pkgs.replace-secret} ${lib.escapeShellArg placeholders.${secret}} ${lib.escapeShellArg cfg.secrets.${secret}.path} "$target"
      '')
      usedSecrets}
    if ${lib.getExe' pkgs.gnugrep "grep"} -Eq '__AGENIX_[0-9a-f]{64}__' "$target"; then
      echo "agenix template ${lib.escapeShellArg name} contains an unresolved placeholder" >&2
      exit 1
    fi
  '';
  render = ''
    export PATH=${lib.makeBinPath [pkgs.coreutils]}:$PATH
    umask 077
    install -d -m 0751 ${generationsDir}
    new_generation=$(mktemp -d ${generationsDir}/.new.XXXXXX)
    trap 'test -z "''${new_generation:-}" || rm -rf -- "$new_generation"' EXIT
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList renderTemplate cfg.templates)}
    old_generation=$(readlink ${templatesDir} 2>/dev/null || true)
    ln -sfn "$new_generation" ${templatesDir}
    new_generation=
    case "$old_generation" in
      ${generationsDir}/*) rm -rf -- "$old_generation" ;;
    esac
  '';
  templateType = lib.types.submodule ({name, ...}: {
    options = {
      content = lib.mkOption {
        type = lib.types.lines;
        description = "Template text containing values from age.placeholder.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "${templatesDir}/${name}";
        readOnly = true;
        description = "Runtime path of the rendered template.";
      };
    };
  });
in {
  options.age = {
    placeholder = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      internal = true;
      readOnly = true;
    };
    templates = lib.mkOption {
      type = lib.types.attrsOf templateType;
      default = {};
      description = "Runtime templates rendered from agenix secrets.";
    };
  };

  config = {
    age.placeholder = placeholders;
    assertions =
      lib.mapAttrsToList (name: _: {
        assertion = builtins.match "[A-Za-z0-9._-]+" name != null;
        message = "age.templates names may only contain letters, digits, dots, underscores, and hyphens: ${name}";
      })
      cfg.templates;

    system.activationScripts.agenixTemplates = {
      deps = lib.optional (cfg.secrets != {}) "agenixChown";
      text = render;
    };
  };
}
