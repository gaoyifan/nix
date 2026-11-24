{
  config,
  inputs,
  pkgs,
  username,
  ...
}: let
  photosExporter = pkgs.icloud-photos-export-app;
  photosExporterApp = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/${photosExporter.bundleName}";
  photosExporterLog = "${config.home.homeDirectory}/Library/Logs/icloud-photos-export.log";
  photosPython = pkgs.python313;
in {
  imports = [
    inputs.agenix.homeManagerModules.default
    inputs.findmy-history.homeManagerModules.source
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
      nh
      photosExporter
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

  services.findmy-source = {
    enable = true;
    host = "100.64.2.80";
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

  home.file.".local/bin/icloud-photos-export" = {
    executable = true;
    text = ''
      #!/bin/sh
      exec ${photosPython.interpreter} ${./icloud-photos-export.py} --trigger ${photosExporter.bundleIdentifier}
    '';
  };
  home.file.".local/bin/osxphotos".source = "${pkgs.osxphotos}/bin/osxphotos";

  launchd.agents.icloud-photos-export = {
    enable = true;
    config = {
      Label = photosExporter.bundleIdentifier;
      ProgramArguments = [
        "${photosExporterApp}/Contents/MacOS/${photosExporter.executableName}"
        "${./icloud-photos-export.py}"
        "--worker"
      ];
      EnvironmentVariables = {
        PYTHONPATH = "${pkgs.osxphotos}/${photosPython.sitePackages}";
      };
      ProcessType = "Background";
      LimitLoadToSessionType = "Aqua";
      StandardOutPath = photosExporterLog;
      StandardErrorPath = photosExporterLog;
    };
  };
}
