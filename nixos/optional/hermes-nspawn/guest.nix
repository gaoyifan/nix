{
  aptProxyAddress,
  config,
  containerName,
  honchoBaseUrl,
  hostPkgs,
  inputs,
  lib,
  newApiBaseUrl,
  pkgs,
  telegramBotApi,
  telegramBotApiBaseUrl,
  userName,
  ...
}: let
  inherit (import ../../common/ssh-keys.nix) sshKeys;
  hermesBasePackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.minimal.override {
    extraDependencyGroups = ["exa" "honcho" "messaging"];
  };
  sitePackages = pkgs.python312.sitePackages;
  # Desktop/TUI uploads live in $HERMES_HOME/images, but Hermes 0.19.0 omits
  # that agent-owned directory from the host-readable media roots used with a
  # container terminal backend. Replace tools.image_source in a derived venv so
  # uploads can reach vision without widening access to arbitrary host paths.
  #
  # A plain PYTHONPATH overlay is insufficient: slash_worker calls
  # harden_import_path(), which moves the sealed import root ahead of
  # PYTHONPATH. Pointing HERMES_PYTHON_SRC_ROOT at the derived venv preserves
  # that protection while selecting the patched module. Remove this override
  # once the pinned Hermes source includes the images root.
  hermesVenv = hermesBasePackage.hermesVenv.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        rm "$out/${sitePackages}/tools"
        cp -rL "${hermesBasePackage.hermesVenv}/${sitePackages}/tools" "$out/${sitePackages}/"
        chmod -R u+w "$out/${sitePackages}/tools"
        substituteInPlace "$out/${sitePackages}/tools/image_source.py" \
          --replace-fail \
            '        home / "cache",  # cache/images, cache/vision, cache/video(s), cache/audio' \
            '        home / "cache",  # cache/images, cache/vision, cache/video(s), cache/audio
          home / "images",  # desktop/TUI uploads'
      '';
  });
  hermesPackage = hermesBasePackage.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        for program in hermes hermes-agent hermes-acp; do
          # PYTHONPATH activates the derived venv while HERMES_PYTHON_SRC_ROOT
          # keeps it first after import-path hardening.
          wrapProgram "$out/bin/$program" \
            --set HERMES_PYTHON_SRC_ROOT "${hermesVenv}/${sitePackages}" \
            --prefix PYTHONPATH : "${hermesVenv}/${sitePackages}"
        done
      '';
    passthru = (old.passthru or {}) // {inherit hermesVenv;};
  });
  honchoConfig = pkgs.writeText "honcho.json" (builtins.toJSON {
    baseUrl = honchoBaseUrl;
    hosts.hermes = {
      enabled = true;
      workspace = containerName;
      peerName = userName;
      aiPeer = containerName;
      pinUserPeer = true;
    };
  });
  newApiCodexPlugin = pkgs.runCommand "newapi-codex" {} ''
    mkdir -p $out
    cp -r ${./newapi-codex}/. $out/
  '';
  managedSkills = pkgs.runCommand "hermes-managed-skills" {} ''
    mkdir -p $out
    cp -rL ${inputs.anthropic-skills}/skills/{docx,xlsx,pdf,pptx} $out/
    cp -rL ${inputs.lark-cli-src}/skills/lark-* $out/
    cp -rL ${./skills/local-whisper-transcription} $out/local-whisper-transcription
  '';
  guestTools = [
    pkgs.agent-browser
    pkgs.chromium
  ];
  terminal = import ./terminal.nix {
    inherit aptProxyAddress lib managedSkills newApiBaseUrl pkgs;
  };
in {
  imports = [inputs.hermes-agent.nixosModules.default];

  nixpkgs.pkgs = hostPkgs;

  networking.hostName = containerName;
  networking.useHostResolvConf = false;
  networking.interfaces.eth0.useDHCP = true;
  networking.firewall.allowedTCPPorts = [
    22
    9119
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  time.timeZone = "Asia/Singapore";

  users.groups.agent.gid = 1000;
  users.users = {
    agent = {
      isNormalUser = true;
      uid = 1000;
      group = "agent";
      home = "/var/lib/hermes";
      createHome = true;
      shell = pkgs.bashInteractive;
      extraGroups = [
        "podman"
      ];
      openssh.authorizedKeys.keys = sshKeys;
    };
    root.openssh.authorizedKeys.keys = sshKeys;
  };
  programs.bash.loginShellInit = ''
    if [[ $USER == agent ]]; then
      export CONTAINER_HOST=unix:///run/podman/podman.sock
    fi
  '';
  virtualisation = {
    podman.enable = true;
    containers.containersConf.settings = {
      engine = {
        runtime = "runsc";
        runtimes.runsc = ["${pkgs.gvisor}/bin/runsc"];
        runtimes_flags.runsc = [
          "platform=kvm"
          "network=host"
          "overlay2=root:self,size=8g"
          "oci-seccomp=true"
          "watchdog-action=panic"
          "kvm-use-cpu-nums=true"
        ];
      };
      containers = {
        env = ["NEWAPI_API_KEY"];
        netns = "host";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/containers/tmp 0700 root root - -"
    "d /var/lib/hermes 0750 agent agent - -"
    "d /var/lib/hermes/ssh 0700 root root - -"
    "d /var/lib/hermes/.hermes/skills 2770 agent agent - -"
    "L+ /var/lib/hermes/.hermes/honcho.json - agent agent - ${honchoConfig}"
  ];

  systemd.services.podman = {
    unitConfig.RequiresMountsFor = "/etc/hermes";
    environment.TMPDIR = "/var/lib/containers/tmp";
    serviceConfig.EnvironmentFile = "/etc/hermes/.env";
  };

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/var/lib/hermes/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
    };
  };

  fonts.packages = [pkgs.noto-fonts-cjk-sans];

  environment.variables = {
    AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;
    HERMES_MANAGED = "true";
  };

  services.hermes-agent = {
    enable = true;
    package = hermesPackage;
    user = "agent";
    group = "agent";
    createUser = false;
    addToSystemPackages = true;
    extraPackages = guestTools;
    extraPlugins = [newApiCodexPlugin];
    settings = {
      model = {
        provider = "newapi";
        default = "gpt-5.6-sol";
        base_url = newApiBaseUrl;
        api_mode = "codex_responses";
      };
      providers.newapi = {
        api = newApiBaseUrl;
        key_env = "NEWAPI_API_KEY";
        default_model = "gpt-5.6-sol";
        transport = "codex_responses";
        models = {
          "codex-auto-review".context_length = 272000;
          "gpt-5.3-codex-spark".context_length = 128000;
          "gpt-5.4".context_length = 272000;
          "gpt-5.4-mini".context_length = 272000;
          "gpt-5.5".context_length = 272000;
          "gpt-5.6-sol".context_length = 272000;
          "gpt-5.6-terra".context_length = 272000;
          "gpt-5.6-luna".context_length = 272000;
        };
      };
      compression.threshold = 0.9;
      auxiliary.title_generation.model = "gpt-5.6-luna";
      memory.provider = "honcho";
      agent.system_prompt = ''
        Never run machine-learning model inference inside the Podman terminal environment. Use external APIs for inference.

        Prefer delegating programming tasks to the Codex CLI through the codex skill.

        Terminal commands run inside a Podman container isolated by gVisor's KVM platform. /workspace and /root are persistent for the task; other container filesystem changes may disappear when the container is replaced. The container does not run systemd, so manage processes directly rather than using systemctl.
      '';
      web.backend = "exa";
      telegram.extra.rich_messages = true;
      gateway.platforms.telegram.extra = lib.optionalAttrs telegramBotApi.enable {
        base_url = "${telegramBotApiBaseUrl}:${toString telegramBotApi.apiPort}/bot";
        base_file_url = "${telegramBotApiBaseUrl}:${toString telegramBotApi.filePort}/file/bot";
      };
      platform_toolsets.telegram = ["hermes-telegram"];
      stt.enabled = false;
      image_gen.provider = "newapi-codex";
      plugins.enabled = ["newapi-codex"];
      skills = {
        disabled = [
          "apple-notes"
          "apple-reminders"
          "audiocraft-audio-generation"
          "claude-code"
          "comfyui"
          "evaluating-llms-harness"
          "findmy"
          "himalaya"
          "imessage"
          "llama-cpp"
          "opencode"
          "openhue"
          "powerpoint"
          "segment-anything-model"
          "serving-llms-vllm"
          "yuanbao"
        ];
        external_dirs = ["${managedSkills}"];
      };
      terminal = {
        backend = "docker";
        container_cpu = 6;
        container_disk = 0;
        container_memory = 8192;
        cwd = "/workspace";
        docker_extra_args = [];
        docker_image = terminal.imageRef;
        docker_volumes = terminal.volumes;
      };
    };
  };

  systemd.services.lark-cli-init = {
    description = "Configure Lark CLI for Hermes";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    unitConfig.RequiresMountsFor = "/etc/hermes /var/lib/hermes";
    environment = {
      HOME = "/var/lib/hermes";
      HERMES_HOME = "/var/lib/hermes/.hermes";
      LARKSUITE_CLI_NO_SKILLS_NOTIFIER = "1";
      LARKSUITE_CLI_NO_UPDATE_NOTIFIER = "1";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "agent";
      Group = "agent";
      EnvironmentFile = "/etc/hermes/.env";
      UMask = "0077";
    };
    script = ''
      printf '%s\n' "$LARK_APP_SECRET" | ${lib.getExe pkgs.lark-cli} config init \
        --app-id "$LARK_APP_ID" \
        --app-secret-stdin \
        --brand feishu \
        --force-init
    '';
  };

  systemd.services.hermes-terminal-image = {
    description = "Load the Hermes terminal image into Podman";
    after = ["podman.socket"];
    requires = ["podman.socket"];
    before = ["hermes-agent.service"];
    unitConfig.RequiresMountsFor = "/var/lib/containers /var/lib/hermes";
    environment = {
      CONTAINER_HOST = "unix:///run/podman/podman.sock";
      TMPDIR = "/var/lib/containers/tmp";
    };
    path = [
      pkgs.coreutils
      config.virtualisation.podman.package
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      image_ref=${lib.escapeShellArg terminal.imageRef}
      state_dir=/var/lib/hermes/podman
      tag_file="$state_dir/terminal-image"

      find "$TMPDIR" -mindepth 1 -delete
      if ! podman image exists "$image_ref"; then
        podman load --input ${terminal.image}
      fi

      install -d -o root -g root -m 0755 "$state_dir"
      deployed_ref=""
      if [[ -f "$tag_file" ]]; then
        read -r deployed_ref < "$tag_file"
      fi

      if [[ "$deployed_ref" != "$image_ref" ]]; then
        containers="$(podman ps --all --quiet --filter label=hermes-agent=1)"
        if [[ -n "$containers" ]]; then
          podman rm --force $containers
        fi
        if [[ -n "$deployed_ref" ]] && podman image exists "$deployed_ref"; then
          podman image rm "$deployed_ref"
        fi

        printf '%s\n' "$image_ref" > "$tag_file.tmp"
        chmod 0644 "$tag_file.tmp"
        mv -f "$tag_file.tmp" "$tag_file"
      fi
    '';
  };

  systemd.services.hermes-agent = {
    after = [
      "hermes-terminal-image.service"
      "lark-cli-init.service"
    ];
    requires = [
      "hermes-terminal-image.service"
      "lark-cli-init.service"
    ];
    unitConfig.RequiresMountsFor = "/etc/hermes /var/lib/hermes";
    path = [config.virtualisation.podman.package];
    environment = {
      AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;
      CONTAINER_HOST = "unix:///run/podman/podman.sock";
      MESSAGING_CWD = lib.mkForce null;
    };
    serviceConfig.EnvironmentFile = "/etc/hermes/.env";
  };

  systemd.services.hermes-dashboard = {
    description = "Hermes Agent Dashboard";
    wantedBy = ["multi-user.target"];
    after = [
      "hermes-terminal-image.service"
      "lark-cli-init.service"
      "network-online.target"
    ];
    wants = ["network-online.target"];
    requires = [
      "hermes-terminal-image.service"
      "lark-cli-init.service"
    ];
    unitConfig.RequiresMountsFor = "/etc/hermes /var/lib/hermes";
    environment = {
      AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;
      CONTAINER_HOST = "unix:///run/podman/podman.sock";
      HERMES_HOME = "/var/lib/hermes/.hermes";
      HERMES_MANAGED = "true";
      HOME = "/var/lib/hermes";
    };
    path =
      [
        hermesPackage
        pkgs.bash
        pkgs.coreutils
        pkgs.git
        config.virtualisation.podman.package
      ]
      ++ guestTools;
    serviceConfig = {
      User = "agent";
      Group = "agent";
      WorkingDirectory = "/var/lib/hermes/workspace";
      EnvironmentFile = "/etc/hermes/.env";
      ExecStart = "${hermesPackage}/bin/hermes dashboard --host 0.0.0.0 --port 9119 --no-open";
      Restart = "always";
      RestartSec = 5;
      UMask = "0007";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = ["/var/lib/hermes"];
      PrivateTmp = true;
    };
  };

  system.stateVersion = "26.05";
}
