{
  inputs,
  pkgs,
}: {
  name = "agenix-templates";

  nodes.machine = {config, ...}: {
    imports = [
      inputs.agenix.nixosModules.default
      (inputs.agenix + "/test/install_ssh_host_keys.nix")
      ../common/agenix-templates.nix
    ];

    services.openssh.enable = true;
    users.users.user1 = {
      isNormalUser = true;
      uid = 1000;
    };

    age.secrets.fixture.file = inputs.agenix + "/example/-leading-hyphen-filename.age";
    age.templates."fixture.env" = {
      content = ''
        FIRST=${config.age.placeholder.fixture}
        SECOND=${config.age.placeholder.fixture}
      '';
    };

    system.stateVersion = "26.05";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test \"$(cat /run/agenix-templates/fixture.env)\" = $'FIRST=filename started with hyphen\\nSECOND=filename started with hyphen'")
    machine.succeed("test \"$(stat -c '%U:%G %a' /run/agenix-templates/fixture.env)\" = 'root:root 400'")
    machine.succeed("test \"$(readlink /run/agenix-templates)\" != \"\"")
  '';
}
