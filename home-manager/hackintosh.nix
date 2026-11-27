{
  config,
  inputs,
  lib,
  pkgs,
  username,
  ...
}: let
  photosExporter = pkgs.icloud-photos-export-app;
  photosExporterSigner = "749207789A0B166A4113137E8EF61800BA2736E1";
  photosExporterBuild = "${builtins.baseNameOf (toString photosExporter)}-${photosExporterSigner}";
  photosExporterApp = "${config.home.homeDirectory}/Library/Application Support/iCloud Photos Exporter/${photosExporterBuild}/${photosExporter.bundleName}";
  photosExporterRequirement = ''=identifier "${photosExporter.bundleIdentifier}" and certificate leaf = H"${photosExporterSigner}"'';
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

  home.activation.installPhotosExporter = lib.hm.dag.entryBetween ["setupLaunchAgents"] ["writeBoundary"] ''
    installPhotosExporter() (
      set -euo pipefail
      app=${lib.escapeShellArg photosExporterApp}
      verify() {
        /usr/bin/codesign --verify --strict -R ${lib.escapeShellArg photosExporterRequirement} "$1"
      }
      if verify "$app" 2>/dev/null; then
        exit 0
      fi

      mkdir -p "$(dirname "$app")"
      staging=$(mktemp -d "$(dirname "$app")/.icloud-photos-export.XXXXXXXX")
      trap 'rm -r "$staging"' EXIT
      next="$staging/${photosExporter.bundleName}"
      /usr/bin/ditto ${lib.escapeShellArg "${photosExporter}/Applications/${photosExporter.bundleName}"} "$next"
      chmod -R u+w "$next"
      /usr/bin/codesign --force --sign ${photosExporterSigner} "$next"
      verify "$next"

      rm -rf "$app"
      mv "$next" "$app"
    )
    run installPhotosExporter
  '';

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
