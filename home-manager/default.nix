# Home Manager configuration
# Shared between standalone home-manager and darwin-integrated home-manager
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  rimeIce = pkgs.fetchFromGitHub {
    owner = "iDvel";
    repo = "rime-ice";
    rev = "51003473600d90ff4b46004a5122ee1b98210606";
    hash = "sha256-4BJrs+PkC4flA7a6ZrATNT+CtUdUuoWKb62Mw5t91q4=";
  };
in {
  imports = [
    ./shell.nix
    ./ssh-auth-sock.nix
    ./neovim.nix
    ./mutagen-dotfiles-sync.nix
    ./restic-systemd-installer.nix
    ../secrets/home.nix
  ];

  home.username = lib.mkDefault "yifan";
  home.homeDirectory = lib.mkDefault (
    if isDarwin
    then "/Users/${config.home.username}"
    else "/home/${config.home.username}"
  );
  home.stateVersion = "25.11"; # Do not change - see home-manager release notes

  home.packages = with pkgs;
    [
      # Git tools
      delta
      difftastic
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
      restic

      # External flake package
      inputs.witr.packages.${stdenv.hostPlatform.system}.default
    ]
    ++ lib.optionals isDarwin [pkgs.lazyssh];

  # Cargo binaries (rust tools installed via cargo install)
  home.sessionPath =
    [
      "${config.home.homeDirectory}/.nix-profile/bin"
      "${config.home.homeDirectory}/.cargo/bin"
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.bun/bin"
    ]
    ++ lib.optionals (!isDarwin) [
      "/home/linuxbrew/.linuxbrew/opt/rustup/bin"
    ];

  # nh (nix helper) configuration
  home.sessionVariables = {
    NH_FLAKE = "${config.home.homeDirectory}/nix";
    BUN_INSTALL = "${config.home.homeDirectory}/.bun";
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
      ".agent".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.agent";
      ".codex/auth.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.codex/auth.json";
      ".codex/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.codex/config.toml";
      ".codex/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.codex/skills";
      ".config/opencode".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.config/opencode";
      ".cursor/cli-config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.cursor/cli-config.json";
      ".local/share/opencode/auth.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.local/share/opencode/auth.json";
      ".gemini/antigravity-cli/antigravity-oauth-token".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.gemini/antigravity-cli/antigravity-oauth-token";
      ".gemini/antigravity-cli/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.gemini/antigravity-cli/settings.json";
      ".config/gh".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.config/gh";
      ".copilot/config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.copilot/config.json";
    })
    (lib.mkIf (config.services.mutagen.dotfileSync.enable && !isDarwin) {
      ".config/cursor/auth.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.syncd-dotfiles/.config/cursor/auth.json";
    })
    (lib.mkIf isDarwin {
      "Library/Rime" = {
        source = rimeIce;
        recursive = true;
      };
      "Library/Rime/rime_ice.custom.yaml".text = ''
        patch:
          "switches/@0/reset": 1
      '';
    })
  ];

  # Enable atuin sync key deployment from secrets module
  services.secrets.atuin.enable = true;

  services.mutagen.dotfileSync = {
    enable = lib.mkDefault config.services.secrets.hasRealFiles;
    host = "mutagen.yfgao.com";
    user = "syncd";
    port = 2221;
    remotePath = "/data/syncd-dotfiles";
  };

  # Auto gc on Linux only - darwin handles this at system level
  nix.gc.automatic = !isDarwin;
}
