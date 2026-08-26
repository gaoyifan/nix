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
  identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
  sessionName = "syncd-dotfiles";
  sessionLabels = {
    managed = "true";
    service = "syncd-dotfiles";
  };
  sessionSelector = lib.concatStringsSep "," (lib.mapAttrsToList (name: value: "${name}==${value}") sessionLabels);
  # Mutagen 0.18.0 parses SCP-style SSH endpoints as user@host:port:path; ssh://... is not recognized by pkg/url.Parse.
  remoteEndpoint = "${cfg.user}@${cfg.host}:${toString cfg.port}:/data/syncd-dotfiles";
  remoteRsyncRoot = "${cfg.user}@${cfg.host}:/data/syncd-dotfiles/";
  rsyncSshCommand = "${sshWrapper}/bin/ssh -F /dev/null -p ${toString cfg.port}";
  ignoredPaths =
    [
      ".codex/archived_sessions"
      ".codex/cache"
      ".codex/history.jsonl"
      ".codex/models_cache.json"
      ".codex/tmp"
      ".codex/.tmp"
      ".codex/version.json"
    ]
    ++ lib.optional (!cfg.syncCodexSessions) ".codex/sessions";
  rsyncExcludeArguments = map (path: "--exclude=/${path}") ignoredPaths;
  sessionCreateArguments = lib.cli.toCommandLineGNU {} {
    compression = "deflate";
    ignore = ignoredPaths;
    label = lib.mapAttrsToList (name: value: "${name}=${value}") sessionLabels;
    mode = "two-way-safe";
    name = sessionName;
    "no-ignore-vcs" = true;
    "scan-mode" = "accelerated";
    "symlink-mode" = "portable";
    "watch-mode" = "portable";
  };
  specHash = builtins.hashString "sha256" (builtins.toJSON {
    inherit identityFile localPath remoteEndpoint sessionCreateArguments;
  });
  mutagenDataEnv = ''
    export MUTAGEN_DATA_DIRECTORY=${mutagenDataDir}
  '';
  mutagenSshEnv =
    mutagenDataEnv
    + ''
      export MUTAGEN_SSH_PATH=${sshWrapper}/bin
      unset SSH_AUTH_SOCK SSH_AGENT_PID
    '';
  mkSshWrapper = name:
    pkgs.writeShellScriptBin name ''
      if [ -f ${lib.escapeShellArg identityFile} ]; then
        exec env -u SSH_AUTH_SOCK -u SSH_AGENT_PID ${pkgs.openssh}/bin/${name} \
          -o IdentityAgent=none \
          -o IdentitiesOnly=yes \
          -o IdentityFile=${lib.escapeShellArg identityFile} \
          -o StrictHostKeyChecking=accept-new \
          "$@"
      fi

      exec ${pkgs.openssh}/bin/${name} "$@"
    '';
  sshWrapper = pkgs.symlinkJoin {
    name = "mutagen-dotfiles-ssh-wrapper";
    paths = [
      (mkSshWrapper "ssh")
      (mkSshWrapper "scp")
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
      ${mutagenSshEnv}

      session_name=${lib.escapeShellArg sessionName}
      service_selector=${lib.escapeShellArg sessionSelector}
      desired_hash="${specHash}"

      mkdir -p ${lib.escapeShellArg localPath} ${lib.escapeShellArg stateDir} ${lib.escapeShellArg mutagenDataDir}

      # This sync uses a dedicated MUTAGEN_DATA_DIRECTORY, so restarting its
      # daemon here won't affect unrelated Mutagen usage. We restart to make
      # sure SSH transport changes (MUTAGEN_SSH_PATH, IdentityFile, etc.)
      # actually apply after `home-manager switch`.
      mutagen daemon stop >/dev/null 2>&1 || true
      mutagen daemon start >/dev/null 2>&1 || true
      if ! mutagen sync list >/dev/null 2>&1; then
        echo "Mutagen daemon is unavailable after start attempt" >&2
        exit 1
      fi

      managed_count="$(mutagen sync list --label-selector "$service_selector" 2>/dev/null | grep -c '^Identifier: ' || true)"
      if [ -f ${lib.escapeShellArg specHashPath} ] \
        && [ "$(cat ${lib.escapeShellArg specHashPath})" = "$desired_hash" ] \
        && [ "$managed_count" -eq 1 ] \
        && mutagen sync resume "$session_name" >/dev/null 2>&1; then
        exit 0
      fi

      if [ "$managed_count" -gt 0 ]; then
        mutagen sync terminate --label-selector "$service_selector" >/dev/null 2>&1 || true
      fi

      mutagen sync create \
        ${lib.escapeShellArgs sessionCreateArguments} \
        ${lib.escapeShellArg localPath} \
        ${lib.escapeShellArg remoteEndpoint}
      printf '%s\n' "$desired_hash" > ${lib.escapeShellArg specHashPath}
    '';
  };
  statusScript = pkgs.writeShellApplication {
    name = "mutagen-dotfiles-status";
    runtimeInputs = [pkgs.mutagen];
    text = ''
      set -euo pipefail
      ${mutagenDataEnv}

      selector=${lib.escapeShellArg sessionSelector}
      exec mutagen sync list --label-selector "$selector" -l
    '';
  };
  resolveConflictsScript = pkgs.writeShellApplication {
    name = "mutagen-dotfiles-resolve-conflicts";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      mutagen
      rsync
    ];
    text = ''
      set -euo pipefail
      ${mutagenSshEnv}

      session_name=${lib.escapeShellArg sessionName}
      selector=${lib.escapeShellArg sessionSelector}
      status_json="$(mutagen sync list --label-selector "$selector" --template '{{json .}}')"
      session_count="$(jq 'length' <<<"$status_json")"

      if [ "$session_count" -ne 1 ]; then
        echo "expected exactly one managed Mutagen session, found $session_count" >&2
        exit 1
      fi

      excluded_conflicts="$(jq '.[0].excludedConflicts // 0' <<<"$status_json")"
      if [ "$excluded_conflicts" -ne 0 ]; then
        echo "Mutagen omitted $excluded_conflicts conflicts from its status output" >&2
        exit 1
      fi

      conflict_count="$(jq '.[0].conflicts | length' <<<"$status_json")"
      if [ "$conflict_count" -eq 0 ]; then
        echo "No conflicts found."
        exit 0
      fi

      mapfile -t conflict_paths < <(
        jq -r '
          .[0].conflicts[]
          | select(
              (.root | test("^\\.codex/sessions/[0-9]{4}/[0-9]{2}/[0-9]{2}/rollout-[A-Za-z0-9._-]+\\.jsonl$"))
              and (.alphaChanges | length == 1)
              and (.betaChanges | length == 1)
              and (.alphaChanges[0].path == .root)
              and (.betaChanges[0].path == .root)
              and (.alphaChanges[0].new.kind == "file")
              and (.betaChanges[0].new.kind == "file")
            )
          | .root
        ' <<<"$status_json"
      )

      tmpdir="$(mktemp -d)"
      session_paused=0
      cleanup() {
        rm -rf "$tmpdir"
        if [ "$session_paused" -eq 1 ]; then
          mutagen sync resume "$session_name" >/dev/null 2>&1 || true
        fi
      }
      trap cleanup EXIT

      mutagen sync pause "$session_name" >/dev/null
      session_paused=1

      for path in "''${conflict_paths[@]}"; do
        alpha_file=${lib.escapeShellArg localPath}/"$path"
        beta_file="$tmpdir/beta"

        if [ ! -f "$alpha_file" ]; then
          echo "Skipping $path: alpha is not a regular file." >&2
          continue
        fi

        if ! rsync -a --ignore-times \
          -e ${lib.escapeShellArg rsyncSshCommand} \
          ${lib.escapeShellArg remoteRsyncRoot}"$path" \
          "$beta_file"; then
          echo "Skipping $path: unable to read beta." >&2
          continue
        fi

        alpha_size="$(wc -c <"$alpha_file")"
        beta_size="$(wc -c <"$beta_file")"

        if cmp -s "$alpha_file" "$beta_file"; then
          echo "Already identical: $path"
        elif [ "$beta_size" -lt "$alpha_size" ] \
          && cmp -s -n "$beta_size" "$beta_file" "$alpha_file" \
          && [ "$(tail -c 1 "$beta_file" | od -An -tu1 | tr -d '[:space:]')" = 10 ]; then
          if ! rsync -a \
            -e ${lib.escapeShellArg rsyncSshCommand} \
            "$alpha_file" \
            ${lib.escapeShellArg remoteRsyncRoot}"$path"; then
            echo "Skipping $path: unable to overwrite beta with alpha." >&2
            continue
          fi
          echo "Overwrote beta with alpha: $path"
        elif [ "$alpha_size" -lt "$beta_size" ] \
          && cmp -s -n "$alpha_size" "$alpha_file" "$beta_file" \
          && [ "$(tail -c 1 "$alpha_file" | od -An -tu1 | tr -d '[:space:]')" = 10 ] \
          && [ "$(wc -c <"$alpha_file")" -eq "$alpha_size" ]; then
          if ! rsync -a \
            -e ${lib.escapeShellArg rsyncSshCommand} \
            ${lib.escapeShellArg remoteRsyncRoot}"$path" \
            "$alpha_file"; then
            echo "Skipping $path: unable to overwrite alpha with beta." >&2
            continue
          fi
          echo "Overwrote alpha with beta: $path"
        else
          echo "Skipping $path: neither file is a complete-line prefix of the other." >&2
        fi
      done

      mutagen sync resume "$session_name" >/dev/null
      session_paused=0
      mutagen sync flush "$session_name" >/dev/null

      status_json="$(mutagen sync list --label-selector "$selector" --template '{{json .}}')"
      remaining_count="$(jq '([.[0].conflicts | length, (.[0].excludedConflicts // 0)] | add)' <<<"$status_json")"
      if [ "$remaining_count" -ne 0 ]; then
        echo "$remaining_count conflict(s) remain." >&2
        exit 1
      fi

      echo "No conflicts remain."
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
      ${mutagenDataEnv}

      selector=${lib.escapeShellArg sessionSelector}
      mutagen sync terminate --label-selector "$selector" >/dev/null 2>&1 || true
      rm -f ${lib.escapeShellArg specHashPath}
    '';
  };
  forceBetaScript = pkgs.writeShellApplication {
    name = "mutagen-dotfiles-force-beta";
    runtimeInputs = with pkgs; [
      coreutils
      mutagen
      rsync
    ];
    text = ''
      set -euo pipefail
      ${mutagenSshEnv}

      session_name=${lib.escapeShellArg sessionName}

      ${lib.getExe reconcileScript}

      cleanup() {
        mutagen sync resume "$session_name" >/dev/null 2>&1 || true
      }
      trap cleanup EXIT

      mutagen sync pause "$session_name" >/dev/null

      mkdir -p ${lib.escapeShellArg localPath}
      rsync -a --delete \
        ${lib.escapeShellArgs rsyncExcludeArguments} \
        -e ${lib.escapeShellArg rsyncSshCommand} \
        ${lib.escapeShellArg remoteRsyncRoot} \
        ${lib.escapeShellArg "${localPath}/"}

      mutagen sync reset "$session_name" >/dev/null
      mutagen sync resume "$session_name" >/dev/null
      mutagen sync flush "$session_name" >/dev/null

      trap - EXIT
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

      key_path="''${1:-${identityFile}.pub}"
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

      # `-i` selects the public key to upload. Authentication can come from
      # the SSH agent or the default SSH configuration for the target.
      exec ssh-copy-id \
        -F /dev/null \
        -i "$key_path" \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
        -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 \
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

    syncCodexSessions = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to include Codex sessions in the Mutagen synchronization session.";
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
      resolveConflictsScript
      resetScript
      forceBetaScript
      uploadKeyScript
    ];

    home.activation.mutagenDotfileSyncKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ ! -f ${lib.escapeShellArg identityFile} ]; then
        ${lib.getExe uploadKeyScript}
      fi
    '';

    home.activation.mutagenDotfileSync = lib.hm.dag.entryAfter ["mutagenDotfileSyncKey"] ''
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
