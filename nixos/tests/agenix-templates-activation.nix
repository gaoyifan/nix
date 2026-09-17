{
  inputs,
  pkgs,
}: let
  inherit (pkgs) lib;
  script = name: extraModule: let
    host = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        {nixpkgs.pkgs = pkgs;}
        inputs.agenix.nixosModules.default
        ../common/agenix-templates.nix
        extraModule
      ];
    };
  in
    pkgs.writeText "agenix-templates-${name}.sh" (
      lib.replaceStrings ["/run/agenix"] ["$TEST_ROOT/agenix"]
      host.config.system.activationScripts.agenixTemplates.text
    );
  empty = script "empty" {};
  rendered = script "rendered" ({config, ...}: {
    age.secrets.fixture.file = inputs.agenix + "/example/-leading-hyphen-filename.age";
    age.templates."fixture.env".content = "VALUE=${config.age.placeholder.fixture}";
  });
  broken = script "broken" {
    age.templates."broken.env".content = "__AGENIX_${builtins.hashString "sha256" "missing"}__";
  };
in
  pkgs.runCommand "agenix-templates-activation" {} ''
    export TEST_ROOT="$TMPDIR/test"
    mkdir -p "$TEST_ROOT/agenix"
    printf fixture > "$TEST_ROOT/agenix/fixture"
    umask 0022
    trap ':' EXIT
    caller_trap=$(trap -p EXIT)
    caller_path=$PATH
    new_generation=caller-owned

    check_caller() {
      test "$(umask)" = 0022
      test "$(trap -p EXIT)" = "$caller_trap"
      test "$PATH" = "$caller_path"
      test "$new_generation" = caller-owned
    }

    # Reproduce the incident ordering: templates run before user-file creation.
    source ${empty}
    check_caller
    touch "$TEST_ROOT/passwd" "$TEST_ROOT/group"
    test "$(stat -c %a "$TEST_ROOT/passwd")" = 644
    test "$(stat -c %a "$TEST_ROOT/group")" = 644
    empty_generation=$(readlink "$TEST_ROOT/agenix-templates")

    source ${rendered}
    check_caller
    test "$(cat "$TEST_ROOT/agenix-templates/fixture.env")" = VALUE=fixture
    test "$(stat -c %a "$TEST_ROOT/agenix-templates/fixture.env")" = 400
    test ! -e "$empty_generation"
    good_generation=$(readlink "$TEST_ROOT/agenix-templates")

    # Both an unresolved placeholder and a missing secret must leave the old
    # generation intact and clean up the failed render.
    rm "$TEST_ROOT/agenix/fixture"
    for failing_script in ${broken} ${rendered}; do
      # Do not use an `if source ...` condition: it suppresses Bash's errexit.
      set +e
      source "$failing_script"
      status=$?
      set -e
      test "$status" -ne 0
      check_caller
      test "$(readlink "$TEST_ROOT/agenix-templates")" = "$good_generation"
      test "$(find "$TEST_ROOT/agenix-templates.d" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 1
    done
    touch "$out"
  ''
