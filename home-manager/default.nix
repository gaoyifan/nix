# Home Manager configuration
# Shared between standalone home-manager and darwin-integrated home-manager
{
  inputs,
  config,
  pkgs,
  lib,
  osConfig ? null,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  isStandaloneLinux = isLinux && osConfig == null;
  rimeIce = pkgs.fetchFromGitHub {
    owner = "iDvel";
    repo = "rime-ice";
    rev = "51003473600d90ff4b46004a5122ee1b98210606";
    hash = "sha256-4BJrs+PkC4flA7a6ZrATNT+CtUdUuoWKb62Mw5t91q4=";
  };
  rimeIceCustom = pkgs.writeText "rime_ice.custom.yaml" ''
    patch:
      "switches/@0/reset": 1
  '';
  cursorCliConfigSource = "${config.home.homeDirectory}/.syncd-dotfiles/.cursor/cli-config.json";
  cursorCliConfigTarget = "${config.home.homeDirectory}/.cursor/cli-config.json";
in {
  imports = [
    inputs.agenix.homeManagerModules.default
    ./shell.nix
    ./ssh-auth-sock.nix
    ./htop.nix
    ./neovim.nix
    ./mutagen-dotfiles-sync.nix
    ../secrets/home.nix
  ];

  home.username = lib.mkDefault "yifan";
  home.homeDirectory = lib.mkDefault (
    if isDarwin
    then "/Users/${config.home.username}"
    else "/home/${config.home.username}"
  );
  home.stateVersion = "26.05";
  home.extraDependencies = [
    (
      if isDarwin
      then inputs.nixpkgs-darwin.outPath
      else inputs.nixpkgs.outPath
    )
  ];

  i18n.glibcLocales = lib.mkIf isLinux (pkgs.glibcLocales.override {
    allLocales = false;
    locales = ["en_US.UTF-8/UTF-8"];
  });

  home.packages = with pkgs;
    [
      # Git tools
      delta
      diffutils

      # Core utilities
      curl
      wget
      tree
      uv
      ripgrep
      just
      fzf

      # lowPrio to avoid conflict with nix-darwin's nh
      (lib.lowPrio nh)

      # Custom package from ./pkgs (via overlay)
      dcv

      # External flake package
      inputs.witr.packages.${stdenv.hostPlatform.system}.default
    ]
    ++ lib.optionals isDarwin [
      pkgs.lazyssh
      pkgs.tssh
    ]
    ++ lib.optionals isLinux [jip];

  # Cargo binaries (rust tools installed via cargo install)
  home.sessionPath =
    [
      "${config.home.homeDirectory}/.nix-profile/bin"
      "${config.home.homeDirectory}/.cargo/bin"
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.bun/bin"
    ]
    ++ lib.optionals isLinux [
      # Keep setuid wrappers (sudo, ...) ahead of the plain copies in
      # /run/current-system/sw/bin, which fail with "must be owned by uid 0".
      "/run/wrappers/bin"
      "/run/current-system/sw/bin"
      "/home/linuxbrew/.linuxbrew/opt/rustup/bin"
    ];

  # nh (nix helper) configuration
  home.sessionVariables =
    {
      NH_FLAKE = "${config.home.homeDirectory}/nix";
      BUN_INSTALL = "${config.home.homeDirectory}/.bun";
    }
    // lib.optionalAttrs isLinux {
      XDG_RUNTIME_DIR = "\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}";
      DBUS_SESSION_BUS_ADDRESS = "\${DBUS_SESSION_BUS_ADDRESS:-unix:path=\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}/bus}";
    };

  programs.git = {
    enable = true;
    package = pkgs.gitMinimal;
    settings = {
      user = {
        name = "Yifan Gao";
        email = "git@yfgao.com";
      };
      push.autoSetupRemote = true;
      # Delta for better diffs
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta.navigate = true;
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
  };

  programs.home-manager.enable = true;

  home.file = lib.mkMerge [
    (lib.mkIf config.services.mutagen.dotfileSync.enable {
      ".agents".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.agents";
      ".pi".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.pi";
      ".config/opencode".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.config/opencode";
      ".local/share/opencode/auth.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.local/share/opencode/auth.json";
      ".gemini/antigravity-cli/antigravity-oauth-token".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.gemini/antigravity-cli/antigravity-oauth-token";
      ".gemini/antigravity-cli/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.gemini/antigravity-cli/settings.json";
      ".config/gh".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.config/gh";
      ".config/.wrangler/config/default.toml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.config/.wrangler/config/default.toml";
      ".copilot/config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.copilot/config.json";
      ".copilot/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.copilot/settings.json";
    })
    (lib.mkIf (config.services.mutagen.dotfileSync.enable && isLinux) {
      ".config/cursor/auth.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.config/cursor/auth.json";
    })
  ];

  home.activation.unlockLegacyRimeSymlinks = lib.mkIf isDarwin (
    lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] ''
      rime_dir="$HOME/Library/Rime"

      if [ -d "$rime_dir" ]; then
        run /usr/bin/find "$rime_dir" -type l -exec /usr/bin/chflags -h nouchg {} +
      fi
    ''
  );

  home.activation.installRimeConfig = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter ["linkGeneration"] ''
      rime_dir="$HOME/Library/Rime"

      run mkdir -p "$rime_dir"

      while IFS= read -r -d "" rime_link; do
        rime_target=$(/usr/bin/readlink "$rime_link")
        case "$rime_target" in
          /nix/store/*)
            run rm "$rime_link"
            ;;
        esac
      done < <(/usr/bin/find "$rime_dir" -type l -print0)

      run cp -RL ${lib.escapeShellArg "${rimeIce}/."} "$rime_dir/"
      run cp ${lib.escapeShellArg rimeIceCustom} "$rime_dir/rime_ice.custom.yaml"
      run chmod -R u+w "$rime_dir"
    ''
  );

  home.activation.cursorCliConfigInit = lib.mkIf config.services.mutagen.dotfileSync.enable (lib.hm.dag.entryAfter ["linkGeneration"] ''
    source=${lib.escapeShellArg cursorCliConfigSource}
    target=${lib.escapeShellArg cursorCliConfigTarget}

    if [ -e "$source" ] && [ ! -e "$target" ] && [ ! -L "$target" ]; then
      run mkdir -p "$(dirname "$target")"
      run cp -p "$source" "$target"
    fi
  '');

  # Keep the user manager alive for runtime-mounted secrets on headless Linux
  # hosts, including sessions created by tssh rather than pam_systemd.
  home.activation.enableLinger = lib.mkIf isStandaloneLinux (
    lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] ''
      if ! PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH" \
        run loginctl enable-linger ${lib.escapeShellArg config.home.username}; then
        PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH" \
          run sudo loginctl enable-linger ${lib.escapeShellArg config.home.username}
      fi
    ''
  );

  # Enable atuin sync key deployment from secrets module
  services.secrets.atuin.enable = true;

  services.mutagen.dotfileSync = {
    enable = lib.mkDefault config.services.secrets.hasRealFiles;
    host = "mutagen.yfgao.com";
    user = "syncd";
    port = 2221;
  };

  # Auto gc on Linux only - darwin handles this at system level
  nix.gc.automatic = isLinux;
}
