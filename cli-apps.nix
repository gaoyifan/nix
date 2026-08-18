{lib}: let
  from = packagePath: {packagePath = lib.toList packagePath;};
  fromMany = packagePath: names:
    lib.genAttrs names (_: from packagePath);
  appSpecs =
    {
      agy = {};
      agenix = {};
      bmon = {};
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
      fd = {};
      file = {};
      gh = {};
      go = from "go";
      gofmt = from "go";
      hexdump = {};
      herdr = {};
      iostat = from "sysstat";
      mcat = {
        preferWrapper = true;
      };
      ncdu = {};
      node = from "nodejs-slim";
      npm = from ["nodejs-slim" "npm"];
      npx = from ["nodejs-slim" "npm"];
      pi = from "pi-coding-agent";
      pi-baseline = {
        packagePath = ["pi-coding-agent-baseline"];
        program = "pi";
      };
      playwright-cli = {};
      redis-cli = from "redis";
      rsync = {};
      ruby = {};
      smartctl = from "smartmontools";
      sqlite3 = from "sqlite";
      telnet = from "inetutils";
      tig = {};
      tokei = {};
      yazi = from "yazi-unwrapped";
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
  resolvePackages = platform: packages:
    lib.mapAttrs (
      name: spec: lib.getAttrFromPath (packagePathOf name spec) packages
    )
    (availableSpecs platform packages);
in {
  mkPackages = {
    pkgs,
    customPackages,
  }: let
    platform = pkgs.stdenv.hostPlatform;
    appPackages = resolvePackages platform (pkgs // customPackages);
    customAppPackages = resolvePackages platform customPackages;
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
    availableAppSpecs = availableSpecs pkgs.stdenv.hostPlatform pkgs;
    nixCacheOptions = [
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
      flakeApp = "git+https://github.com/gaoyifan/nix.git?ref=main&shallow=1#apps.${pkgs.stdenv.hostPlatform.system}.${app}";
      resolveProgram = ''
        program: let
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

        resolution="$(nix eval ${lib.escapeShellArgs nixCacheOptions} --raw ${lib.escapeShellArg "${flakeApp}.program"} --apply ${lib.escapeShellArg resolveProgram})" || exit $?
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
