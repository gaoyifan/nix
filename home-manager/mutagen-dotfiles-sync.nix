{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mutagen.dotfileSync;
  isDarwin = pkgs.stdenv.isDarwin;
  localPath = "${config.home.homeDirectory}/.syncd-dotfiles";
  specPath = "${config.home.homeDirectory}/.config/mutagen-dotfiles-sync/spec.json";
  stateDir = "${config.home.homeDirectory}/.local/state/mutagen-dotfiles-sync";
  specHashPath = "${stateDir}/spec-hash";
  reconcileScript = pkgs.writeShellApplication {
    name = "mutagen-dotfiles-reconcile";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gawk
      mutagen
    ];
    text = ''
      set -euo pipefail

      host_name="$(/bin/hostname -s)"
      session_name="syncd-dotfiles-$host_name"
      host_selector="service==syncd-dotfiles,host==$host_name"
      # Mutagen 0.18.0 parses SCP-style SSH endpoints as user@host:port:path; ssh://... is not recognized by pkg/url.Parse.
      remote_endpoint="${cfg.user}@${cfg.host}:${toString cfg.port}:${cfg.remotePath}"
      desired_hash="$(sha256sum ${lib.escapeShellArg specPath} | awk '{print $1}')"

      ensure_daemon() {
        if mutagen sync list >/dev/null 2>&1; then
          return 0
        fi

        mutagen daemon start >/dev/null 2>&1 || true

        if mutagen sync list >/dev/null 2>&1; then
          return 0
        fi

        echo "Mutagen daemon is unavailable after start attempt" >&2
        return 1
      }

      create_session() {
        mutagen sync create \
          --name "$session_name" \
          --label "managed=true" \
          --label "service=syncd-dotfiles" \
          --label "host=$host_name" \
          --mode=two-way-safe \
          --watch-mode=portable \
          --ignore-vcs \
          --symlink-mode=portable \
          --scan-mode=accelerated \
          --compression=deflate \
          ${lib.escapeShellArg localPath} \
          "$remote_endpoint"
      }

      mkdir -p ${lib.escapeShellArg localPath} ${lib.escapeShellArg stateDir}
      ensure_daemon

      session_exists=0
      managed_count="$(mutagen sync list --label-selector "$host_selector" 2>/dev/null | grep -c '^Identifier: ' || true)"
      if mutagen sync resume "$session_name" >/dev/null 2>&1; then
        session_exists=1
      fi

      if [ -f ${lib.escapeShellArg specHashPath} ] \
        && [ "$(cat ${lib.escapeShellArg specHashPath})" = "$desired_hash" ] \
        && [ "$session_exists" -eq 1 ] \
        && [ "$managed_count" -eq 1 ]; then
        exit 0
      fi

      if [ "$managed_count" -gt 0 ]; then
        mutagen sync terminate --label-selector "$host_selector" >/dev/null 2>&1 || true
      fi

      create_session
      printf '%s\n' "$desired_hash" > ${lib.escapeShellArg specHashPath}
    '';
  };
  statusScript = pkgs.writeShellApplication {
    name = "mutagen-dotfiles-status";
    runtimeInputs = [pkgs.mutagen];
    text = ''
      set -euo pipefail

      session_name="syncd-dotfiles-$(/bin/hostname -s)"
      exec mutagen sync list "$session_name" -l
    '';
  };
  resetScript = pkgs.writeShellApplication {
    name = "mutagen-dotfiles-reset";
    runtimeInputs = with pkgs; [
      coreutils
      mutagen
    ];
    text = ''
      set -euo pipefail

      session_name="syncd-dotfiles-$(/bin/hostname -s)"
      mutagen sync terminate "$session_name" >/dev/null 2>&1 || true
      rm -f ${lib.escapeShellArg specHashPath}
    '';
  };
  uploadKeyScript = pkgs.writeShellApplication {
    name = "mutagen-dotfiles-upload-pubkey";
    runtimeInputs = with pkgs; [
      coreutils
      openssh
    ];
    text = ''
      set -euo pipefail

      if [ "$#" -gt 1 ]; then
        echo "usage: mutagen-dotfiles-upload-pubkey [public-key-path]" >&2
        exit 1
      fi

      key_path="''${1:-$HOME/.ssh/id_ed25519.pub}"
      private_key_path="''${key_path%.pub}"

      if [ "$#" -eq 0 ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"

        if [ ! -f "$private_key_path" ]; then
          ssh-keygen -q -t ed25519 -N "" -f "$private_key_path"
        fi

        if [ ! -f "$key_path" ]; then
          ssh-keygen -y -f "$private_key_path" > "$key_path"
          chmod 600 "$key_path"
        fi
      fi

      if [ ! -f "$key_path" ]; then
        echo "public key not found: $key_path" >&2
        exit 1
      fi

      key_line="$(tr -d '\r\n' < "$key_path")"
      if [ -z "$key_line" ]; then
        echo "public key is empty: $key_path" >&2
        exit 1
      fi

      exec ssh-copy-id -i "$key_path" -p ${toString cfg.port} ${cfg.user}@${cfg.host}
    '';
  };
  daemonServiceName = "mutagen-daemon-start";
in {
  options.services.mutagen.dotfileSync = {
    enable = lib.mkEnableOption "Mutagen sync for ~/.syncd-dotfiles";

    host = lib.mkOption {
      type = lib.types.str;
      description = "SSH hostname for the central dotfiles sync server.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "SSH username for the central dotfiles sync server.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "SSH port for the central dotfiles sync server.";
    };

    remotePath = lib.mkOption {
      type = lib.types.str;
      default = "/data/syncd-dotfiles";
      description = "Remote path inside the SSH container that stores the shared dotfiles.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.host != "" && cfg.user != "";
        message = "services.mutagen.dotfileSync.host and user must be set when enabling dotfiles sync.";
      }
    ];

    home.packages = [
      pkgs.mutagen
      reconcileScript
      statusScript
      resetScript
      uploadKeyScript
    ];

    home.file.".config/mutagen-dotfiles-sync/spec.json".text = builtins.toJSON {
      inherit localPath;
      host = cfg.host;
      user = cfg.user;
      port = cfg.port;
      remotePath = cfg.remotePath;
      mode = "two-way-safe";
      watchMode = "portable";
      ignoreVcs = true;
      symlinkMode = "portable";
      scanMode = "accelerated";
      compression = "deflate";
    };

    home.activation.mutagenDotfileSync = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${lib.getExe reconcileScript} || true
    '';

    systemd.user.services = lib.mkIf (!isDarwin) {
      "${daemonServiceName}" = {
        Unit = {
          Description = "Start Mutagen daemon";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.mutagen}/bin/mutagen daemon start";
          RemainAfterExit = true;
        };
        Install = {
          WantedBy = ["default.target"];
        };
      };
    };

    launchd.agents = lib.mkIf isDarwin {
      "${daemonServiceName}" = {
        enable = true;
        config = {
          ProgramArguments = [
            "${pkgs.mutagen}/bin/mutagen"
            "daemon"
            "start"
          ];
          RunAtLoad = true;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/${daemonServiceName}.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/${daemonServiceName}.log";
        };
      };
    };
  };
}
