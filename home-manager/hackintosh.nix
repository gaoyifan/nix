{
  config,
  inputs,
  pkgs,
  username,
  ...
}: {
  imports = [
    inputs.agenix.homeManagerModules.default
    ./shell.nix
    ./ssh-auth-sock.nix
    ./htop.nix
    ./neovim.nix
    ./mutagen-dotfiles-sync.nix
    ../secrets/home.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/Users/${username}";
    stateVersion = "26.05";
    packages = with pkgs; [
      curl
      delta
      diffutils
      fzf
      just
      neovim
      nh
      ripgrep
      tree
      wget
    ];
    sessionPath = [
      "${config.home.homeDirectory}/.nix-profile/bin"
      "${config.home.homeDirectory}/.local/bin"
    ];
    sessionVariables.NH_FLAKE = "${config.home.homeDirectory}/nix";
    extraDependencies = [
      inputs.nixpkgs.outPath
      inputs.nixpkgs-darwin.outPath
    ];
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
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta.navigate = true;
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
  };
}
