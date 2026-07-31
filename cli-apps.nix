{lib}: let
  ansibleCommands = [
    "ansible"
    "ansible-config"
    "ansible-console"
    "ansible-doc"
    "ansible-galaxy"
    "ansible-inventory"
    "ansible-playbook"
    "ansible-pull"
    "ansible-test"
    "ansible-vault"
  ];
  appSpecs =
    {
      agy = {};
      codex = {};
      copilot = {wrapperArgs = ["--yolo"];};
      copilot-cli = {enableWrapper = false;};
      cursor-agent = {};
      cursor-cli = {enableWrapper = false;};
      difftastic = {wrapperName = "difft";};
      fd = {};
      file = {};
      gh = {};
      go = {};
      gofmt = {program = "gofmt";};
      hexdump = {};
      mcat = {};
      node = {};
      npm = {program = "npm";};
      npx = {program = "npx";};
      pi = {};
      pi-baseline = {};
      playwright-cli = {};
      redis-cli = {program = "redis-cli";};
      ruby = {};
      sqlite3 = {};
      tokei = {};
      yazi = {};
    }
    // lib.genAttrs ansibleCommands (program: {inherit program;});
in {
  mkPackages = {
    pkgs,
    customPackages,
  }:
    customPackages
    // lib.genAttrs ansibleCommands (
      _:
        pkgs.ansible
    )
    // {
      copilot = customPackages.copilot-cli;
      cursor-agent = customPackages.cursor-cli;
      difftastic = pkgs.difftastic;
      fd = pkgs.fd;
      file = pkgs.file;
      gh = pkgs.gh;
      go = pkgs.go;
      gofmt = pkgs.go;
      hexdump = pkgs.hexdump;
      node = pkgs.nodejs-slim;
      npm = pkgs.nodejs-slim.npm;
      npx = pkgs.nodejs-slim.npm;
      pi = customPackages.pi-coding-agent;
      pi-baseline = customPackages.pi-coding-agent-baseline;
      redis-cli = pkgs.redis;
      ruby = pkgs.ruby;
      sqlite3 = pkgs.sqlite;
      tokei = pkgs.tokei;
      yazi = pkgs.yazi-unwrapped;
    };

  mkApps = packages:
    lib.mapAttrs (name: spec: {
      type = "app";
      program =
        if spec ? program
        then lib.getExe' packages.${name} spec.program
        else lib.getExe packages.${name};
      meta = packages.${name}.meta;
    })
    appSpecs;

  mkHomeManager = pkgs: let
    relBinDir = ".local/share/nix-lazy-apps/bin";
    nixRunCacheOptions = [
      "--option"
      "extra-substituters"
      "https://nix-cache.yfgao.net?priority=50"
      "--option"
      "extra-trusted-public-keys"
      "nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4="
    ];
    completions = pkgs.runCommand "dynamic-cli-completions" {} ''
      install -Dm644 ${pkgs.fd}/share/zsh/site-functions/_fd \
        "$out/share/zsh/site-functions/_fd"
      install -Dm644 ${pkgs.gh}/share/zsh/site-functions/_gh \
        "$out/share/zsh/site-functions/_gh"
      install -Dm644 ${pkgs.yazi-unwrapped}/share/zsh/site-functions/_yazi \
        "$out/share/zsh/site-functions/_yazi"
      install -Dm644 ${pkgs.mcat}/share/zsh/site-functions/_mcat \
        "$out/share/zsh/site-functions/_mcat"
    '';
    mkWrapper = name: app: args: let
      appArgs = lib.optionalString (args != []) " ${lib.escapeShellArgs args}";
    in
      pkgs.writeShellScript name ''
        exec nix run ${lib.escapeShellArgs nixRunCacheOptions} "git+https://github.com/gaoyifan/nix.git?ref=main&shallow=1#${app}" --${appArgs} "$@"
      '';
    wrapperFiles = lib.mapAttrs' (
      app: spec: let
        name = spec.wrapperName or app;
      in
        lib.nameValuePair "${relBinDir}/${name}" {
          source = mkWrapper name app (spec.wrapperArgs or []);
        }
    ) (lib.filterAttrs (_name: spec: spec.enableWrapper or true) appSpecs);
  in {
    inherit completions relBinDir wrapperFiles;
  };
}
