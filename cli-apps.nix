{lib}: let
  from = packagePath: {packagePath = lib.toList packagePath;};
  appSpecs = rec {
    agy = {};
    ansible = from "ansible";
    ansible-config = ansible;
    ansible-console = ansible;
    ansible-doc = ansible;
    ansible-galaxy = ansible;
    ansible-inventory = ansible;
    ansible-playbook = ansible;
    ansible-pull = ansible;
    ansible-test = ansible;
    ansible-vault = ansible;
    codex = {};
    copilot = {
      packagePath = ["copilot-cli"];
      wrapperArgs = ["--yolo"];
    };
    copilot-cli = {
      enableWrapper = false;
      program = "copilot";
    };
    cursor-agent = from "cursor-cli";
    cursor-cli = {
      enableWrapper = false;
      program = "cursor-agent";
    };
    difftastic = {
      program = "difft";
      wrapperName = "difft";
    };
    fd = {};
    file = {};
    gh = {};
    go = from "go";
    gofmt = go;
    hexdump = {};
    mcat = {};
    node = from "nodejs-slim";
    npm = from ["nodejs-slim" "npm"];
    npx = npm;
    pi = from "pi-coding-agent";
    pi-baseline = {
      packagePath = ["pi-coding-agent-baseline"];
      program = "pi";
    };
    playwright-cli = {};
    redis-cli = from "redis";
    ruby = {};
    sqlite3 = from "sqlite";
    tokei = {};
    yazi = from "yazi-unwrapped";
  };
  packagePathOf = name: spec: spec.packagePath or [name];
  availableSpecs = packages:
    lib.filterAttrs (
      name: spec: lib.hasAttrByPath (packagePathOf name spec) packages
    )
    appSpecs;
  resolvePackages = packages:
    lib.mapAttrs (
      name: spec: lib.getAttrFromPath (packagePathOf name spec) packages
    )
    (availableSpecs packages);
in {
  mkPackages = {
    pkgs,
    customPackages,
  }: let
    appPackages = resolvePackages (pkgs // customPackages);
    customAppPackages = resolvePackages customPackages;
  in
    customPackages
    // appPackages
    // {
      cli-apps-cache = pkgs.linkFarm "cli-apps-cache" (
        lib.mapAttrsToList (name: path: {inherit name path;}) customAppPackages
      );
    };

  mkApps = packages:
    lib.mapAttrs (name: spec: {
      type = "app";
      program = lib.getExe' packages.${name} (spec.program or name);
      meta = packages.${name}.meta;
    })
    (lib.intersectAttrs packages appSpecs);

  mkHomeManager = pkgs: let
    relBinDir = ".local/share/nix-lazy-apps/bin";
    availableAppSpecs = availableSpecs pkgs;
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
    ) (lib.filterAttrs (_name: spec: spec.enableWrapper or true) availableAppSpecs);
  in {
    inherit completions relBinDir wrapperFiles;
  };
}
