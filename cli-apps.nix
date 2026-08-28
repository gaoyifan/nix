{lib}: let
  from = packagePath: {packagePath = lib.toList packagePath;};
  fromMany = packagePath: names:
    lib.genAttrs names (_: from packagePath);
  appSpecs =
    {
      agy = {};
      agenix = {};
      asciinema = {};
      bmon = {};
      cargo-binstall = {};
      codex = {};
      codex-reindex = {};
      copilot = {
        packagePath = ["copilot-cli"];
        wrapperArgs = ["--yolo"];
      };
      copilot-cli = {
        enableWrapper = false;
        program = "copilot";
      };
      cursor-agent = {
        packagePath = ["cursor-cli"];
        wrapperArgs = ["--disable-auto-update"];
      };
      cursor-cli = {
        enableWrapper = false;
        program = "cursor-agent";
      };
      difftastic = {
        program = "difft";
        wrapperName = "difft";
      };
      doctl = {};
      eget = {};
      exiftool = {};
      fd = {};
      file = {};
      gh = {};
      go = from "go";
      gofmt = from "go";
      hexdump = {};
      herdr = {};
      iostat = from "sysstat";
      loft = {};
      mcat = {
        preferWrapper = true;
      };
      ncdu = {};
      node = from "nodejs-slim";
      npm = from ["nodejs-slim" "npm"];
      npx = from ["nodejs-slim" "npm"];
      nvtop = from ["nvtopPackages" "full"];
      nylon-health = from "nylon-health-runner";
      pi = from "pi-coding-agent";
      playwright-cli = {};
      pv = {};
      redis-cli = from "redis";
      rsync = {};
      ruby = {};
      smartctl = from "smartmontools";
      sqlite3 = from "sqlite";
      step = from "step-cli";
      telnet = from "inetutils";
      tig = {};
      tmate = {};
      tokei = {};
      wrangler = {};
      yazi = from "yazi-unwrapped";
      yarn = {};
    }
    // fromMany "ansible" [
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
    ]
    // fromMany "renameutils" [
      "deurlname"
      "icmd"
      "icp"
      "imv"
      "qcmd"
      "qcp"
      "qmv"
    ]
    // fromMany "rustup" [
      "cargo"
      "cargo-clippy"
      "cargo-fmt"
      "cargo-miri"
      "clippy-driver"
      "rls"
      "rust-analyzer"
      "rust-gdb"
      "rust-gdbgui"
      "rust-lldb"
      "rustc"
      "rustdoc"
      "rustfmt"
      "rustup"
    ];
  packagePathOf = name: spec: spec.packagePath or [name];
  availableSpecs = platform: packages:
    lib.filterAttrs (
      name: spec: let
        package = lib.attrByPath (packagePathOf name spec) null packages;
      in
        package != null && lib.meta.availableOn platform package
    )
    appSpecs;
  resolvePackages = specs: packages:
    lib.mapAttrs (
      name: spec: lib.getAttrFromPath (packagePathOf name spec) packages
    )
    specs;
  mkApps = packages:
    lib.mapAttrs (name: spec: {
      type = "app";
      program = lib.getExe' packages.${name} (spec.program or name);
      meta = packages.${name}.meta;
    })
    (lib.intersectAttrs packages appSpecs);
in {
  mkPackages = {
    pkgs,
    customPackages,
  }: let
    platform = pkgs.stdenv.hostPlatform;
    availablePackages = pkgs // customPackages;
    appPackages = resolvePackages (availableSpecs platform availablePackages) availablePackages;
    customAppPackages = resolvePackages (availableSpecs platform customPackages) customPackages;
  in
    customPackages
    // appPackages
    // {
      cli-apps-cache = pkgs.linkFarm "cli-apps-cache" (
        lib.mapAttrsToList (name: path: {inherit name path;}) customAppPackages
      );
    };

  inherit mkApps;
  mkLazyApps = packages: mkApps (resolvePackages appSpecs packages);

  mkHomeManager = pkgs: let
    relBinDir = ".local/share/nix-lazy-apps/bin";
    availableAppSpecs = availableSpecs pkgs.stdenv.hostPlatform pkgs;
    cacheSettings = import ./nix-cache.nix;
    nixCacheOptions = [
      "--option"
      "extra-substituters"
      (lib.concatStringsSep " " cacheSettings.extra-substituters)
      "--option"
      "extra-trusted-public-keys"
      (lib.concatStringsSep " " cacheSettings.extra-trusted-public-keys)
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
      nixpkgsInput =
        if pkgs.stdenv.isDarwin
        then "nixpkgs-darwin"
        else "nixpkgs";
      resolveExpression = ''
        let
          flake = builtins.getFlake "git+https://github.com/gaoyifan/nix.git?ref=main&shallow=1";
          system = ${builtins.toJSON pkgs.stdenv.hostPlatform.system};
          pkgs = import flake.inputs.${nixpkgsInput} {
            inherit system;
            config.allowUnfree = true;
          };
          customPackages = import (flake.outPath + "/pkgs") {
            inputs = flake.inputs;
            inherit pkgs;
          };
          cliApps = import (flake.outPath + "/cli-apps.nix") {inherit (pkgs) lib;};
          program = (builtins.getAttr ${builtins.toJSON app} (cliApps.mkLazyApps (pkgs // customPackages))).program;
          context = builtins.getContext program;
          drvPath = builtins.head (builtins.attrNames context);
        in
          "''${builtins.unsafeDiscardStringContext program} ''${drvPath}^''${builtins.head context.''${drvPath}.outputs}"
      '';
    in
      pkgs.writeShellScript name ''
        cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/nix-lazy-apps"
        cache_file="$cache_dir/${app}"
        printf -v now '%(%s)T' -1

        if [[ -r "$cache_file" ]] \
          && read -r cached_at program < "$cache_file" \
          && [[ $cached_at =~ ^[0-9]+$ ]] \
          && ((now >= cached_at && now - cached_at < 3600)) \
          && [[ -x $program ]]; then
          exec "$program"${appArgs} "$@"
        fi

        resolution="$(nix eval ${lib.escapeShellArgs nixCacheOptions} --impure --raw --expr ${lib.escapeShellArg resolveExpression})" || exit $?
        read -r program installable <<< "$resolution"

        if [[ ! -x "$program" ]]; then
          nix build ${lib.escapeShellArgs nixCacheOptions} --no-link "$installable" || exit $?
        fi

        mkdir -p "$cache_dir"
        printf '%s %s\n' "$now" "$program" > "$cache_file"
        exec "$program"${appArgs} "$@"
      '';
    wrapperFiles = lib.mapAttrs' (
      app: spec: let
        name = spec.wrapperName or app;
        binDir =
          if spec.preferWrapper or false
          then ".local/bin"
          else relBinDir;
      in
        lib.nameValuePair "${binDir}/${name}" {
          source = mkWrapper name app (spec.wrapperArgs or []);
        }
    ) (lib.filterAttrs (_name: spec: spec.enableWrapper or true) availableAppSpecs);
  in {
    inherit completions relBinDir wrapperFiles;
  };
}
