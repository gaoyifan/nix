{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mutagen.dotfileSync;
  isDarwin = pkgs.stdenv.isDarwin;
  localPath = "${config.home.homeDirectory}/.syncd-dotfiles";
  stateDir = "${config.home.homeDirectory}/.local/state/mutagen-dotfiles-sync";
  specHashPath = "${stateDir}/spec-hash";
  mutagenDataDir = "${stateDir}/mutagen-data";
  identityFile = cfg.identityFile;
  specHash = builtins.hashString "sha256" (builtins.toJSON {
    inherit localPath;
    host = cfg.host;
    user = cfg.user;
    port = cfg.port;
    remotePath = cfg.remotePath;
    identityFile = cfg.identityFile;
    mode = "two-way-safe";
    watchMode = "portable";
    ignoreVcs = true;
    symlinkMode = "portable";
    scanMode = "accelerated";
    compression = "deflate";
  });
  sshWrapper = pkgs.symlinkJoin {
    name = "mutagen-dotfiles-ssh-wrapper";
    paths = [
      (pkgs.writeShellScriptBin "ssh" ''
        if [ -f ${lib.escapeShellArg identityFile} ]; then
          exec env -u SSH_AUTH_SOCK -u SSH_AGENT_PID ${pkgs.openssh}/bin/ssh \
            -o IdentityAgent=none \
            -o IdentitiesOnly=yes \
            -o IdentityFile=${lib.escapeShellArg identityFile} \
            "$@"
        fi

        exec ${pkgs.openssh}/bin/ssh "$@"
      '')
      (pkgs.writeShellScriptBin "scp" ''
        if [ -f ${lib.escapeShellArg identityFile} ]; then
          exec env -u SSH_AUTH_SOCK -u SSH_AGENT_PID ${pkgs.openssh}/bin/scp \
            -o IdentityAgent=none \
            -o IdentitiesOnly=yes \
            -o IdentityFile=${lib.escapeShellArg identityFile} \
            "$@"
        fi

        exec ${pkgs.openssh}/bin/scp "$@"
      '')
    ];
  };
  reconcileScript = pkgs.writeShellApplication {
    name = "mutagen-dotfiles-reconcile";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      mutagen
    ];
    text = ''
      set -euo pipefail
      export MUTAGEN_DATA_DIRECTORY=${mutagenDataDir}
      export MUTAGEN_SSH_PATH=${sshWrapper}/bin
      unset SSH_AUTH_SOCK SSH_AGENT_PID

      host_name="$(/bin/hostname -s)"
      session_name="syncd-dotfiles-$host_name"
      service_selector="managed==true,service==syncd-dotfiles"
      # Mutagen 0.18.0 parses SCP-style SSH endpoints as user@host:port:path; ssh://... is not recognized by pkg/url.Parse.
      remote_endpoint="${cfg.user}@${cfg.host}:${toString cfg.port}:${cfg.remotePath}"
      desired_hash="${specHash}"

      ensure_daemon() {
        # This sync uses a dedicated MUTAGEN_DATA_DIRECTORY, so restarting its
        # daemon here won't affect unrelated Mutagen usage. We restart to make
        # sure SSH transport changes (MUTAGEN_SSH_PATH, IdentityFile, etc.)
        # actually apply after `home-manager switch`.
        mutagen daemon stop >/dev/null 2>&1 || true
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

      mkdir -p ${lib.escapeShellArg localPath} ${lib.escapeShellArg stateDir} ${lib.escapeShellArg mutagenDataDir}
      ensure_daemon

      session_exists=0
      managed_count="$(mutagen sync list --label-selector "$service_selector" 2>/dev/null | grep -c '^Identifier: ' || true)"
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
        mutagen sync terminate --label-selector "$service_selector" >/dev/null 2>&1 || true
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
      export MUTAGEN_DATA_DIRECTORY=${mutagenDataDir}

      selector="managed==true,service==syncd-dotfiles"
      exec mutagen sync list --label-selector "$selector" -l
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
      export MUTAGEN_DATA_DIRECTORY=${mutagenDataDir}

      selector="managed==true,service==syncd-dotfiles"
      mutagen sync terminate --label-selector "$selector" >/dev/null 2>&1 || true
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

      key_path="''${1:-${cfg.identityFile}.pub}"
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

      # `-i` selects the public key to upload. `-f` skips ssh-copy-id's
      # private-key preflight so authentication can come from the SSH agent.
      exec ssh-copy-id \
        -f \
        -i "$key_path" \
        -p ${toString cfg.port} \
        ${cfg.user}@${cfg.host}
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

    identityFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.ssh/id_ed25519";
      description = "SSH private key file used by Mutagen for the central sync server.";
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
          Environment = [
            "MUTAGEN_DATA_DIRECTORY=${mutagenDataDir}"
            "MUTAGEN_SSH_PATH=${sshWrapper}/bin"
            "SSH_AUTH_SOCK="
            "SSH_AGENT_PID="
          ];
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
          EnvironmentVariables = {
            MUTAGEN_DATA_DIRECTORY = "${mutagenDataDir}";
            MUTAGEN_SSH_PATH = "${sshWrapper}/bin";
            SSH_AUTH_SOCK = "";
            SSH_AGENT_PID = "";
          };
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
