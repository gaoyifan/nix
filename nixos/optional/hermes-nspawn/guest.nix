{
  aptProxyAddress,
  codexApiBaseUrl,
  config,
  containerName,
  dashboardPublicUrl,
  hostPkgs,
  inputs,
  lib,
  newApiBaseUrl,
  pkgs,
  telegramBotApi,
  telegramBotApiBaseUrl,
  ...
}: let
  inherit (import ../../common/ssh-keys.nix) sshKeys;
  hermesPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.minimal.override {
    extraDependencyGroups = ["exa" "honcho" "messaging"];
  };
  initialUserConfig = pkgs.writeText "hermes-initial-user-config.yaml" (builtins.toJSON {
    stt.enabled = false;
    plugins.enabled = [
      "newapi-codex"
      "weixin-channel"
    ];
  });
  newApiCodexPlugin = pkgs.runCommand "newapi-codex" {} ''
    mkdir -p $out
    cp -r ${./newapi-codex}/. $out/
  '';
  weixinChannelPlugin = pkgs.runCommand "weixin-channel" {} ''
    install -Dm0444 ${./weixin-channel/plugin.yaml} $out/plugin.yaml
    install -Dm0444 ${./weixin-channel/__init__.py} $out/__init__.py
  '';
  managedSkills = pkgs.runCommand "hermes-managed-skills" {} ''
    mkdir -p $out
    cp -rL ${inputs.anthropic-skills}/skills/{docx,xlsx,pdf,pptx} $out/
    cp -rL ${inputs.lark-cli-src}/skills/lark-* $out/
    cp -rL ${./skills/audio-transcription} $out/audio-transcription
    cp -rL ${inputs.open-kimi-ppt-skill}/skills/open-kimi-ppt $out/open-kimi-ppt
  '';
  guestTools = [
    pkgs.agent-browser
    pkgs.chromium
    pkgs.nodejs_22
    pkgs.uv
  ];
  podmanRuntimeDir = "/run/hermes-podman";
  podmanTmpDir = "/var/lib/hermes/podman-tmp";
  terminal = import ./terminal.nix {
    inherit aptProxyAddress lib managedSkills newApiBaseUrl pkgs;
  };
in {
  imports = [inputs.hermes-agent.nixosModules.default];

  nixpkgs.pkgs = hostPkgs;

  system.build.hermesTerminalImage = terminal.image;

  networking.hostName = containerName;
  networking.useHostResolvConf = false;
  networking.interfaces.eth0.useDHCP = true;
  networking.firewall.allowedTCPPorts = [
    22
    9119
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  users.groups.agent.gid = 1000;
  users.users = {
    agent = {
      isNormalUser = true;
      uid = 1000;
      group = "agent";
      home = "/var/lib/hermes";
      createHome = true;
      shell = pkgs.bashInteractive;
      subUidRanges = [
        {
          startUid = 100000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 100000;
          count = 65536;
        }
      ];
      openssh.authorizedKeys.keys = sshKeys;
    };
    root.openssh.authorizedKeys.keys = sshKeys;
  };
  virtualisation = {
    podman.enable = true;
    containers.containersConf.settings = {
      engine = {
        cgroup_manager = "cgroupfs";
        runtime = "runsc";
        runtimes.runsc = ["${pkgs.gvisor}/bin/runsc"];
        runtimes_flags.runsc = [
          "platform=kvm"
          "network=host"
          "overlay2=root:self,size=8g"
          "oci-seccomp=true"
          "watchdog-action=panic"
          "kvm-use-cpu-nums=true"
          "directfs=false"
          "ignore-cgroups=true"
        ];
      };
      containers = {
        env = ["NEWAPI_API_KEY"];
        netns = "host";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/hermes 0750 agent agent - -"
    "d ${podmanTmpDir} 0700 agent agent - -"
    # Rootless Podman persists its first RunRoot in the storage database.
    "d ${podmanRuntimeDir} 0700 agent agent - -"
    "d /var/lib/hermes/.ssh 0700 agent agent - -"
    "d /var/lib/hermes/ssh 0700 root root - -"
    "d /var/lib/hermes/.hermes/skills 2770 agent agent - -"
    "d /var/lib/hermes-ssh 0755 root root - -"
    "d /var/lib/hermes-ssh/agent 0700 agent agent - -"
    "f /var/lib/hermes-ssh/agent/authorized_keys 0600 agent agent - -"
    "L+ /var/lib/hermes/.ssh/authorized_keys - agent agent - /var/lib/hermes-ssh/agent/authorized_keys"
    "L+ /workspace - - - - /var/lib/hermes/workspace"
    "L+ /home/agent - - - - /workspace"
    "L+ /var/lib/hermes/.hermes/honcho.json - agent agent - /run/hermes-secrets/honcho.json"
  ];

  services.openssh = {
    enable = true;
    authorizedKeysInHomedir = false;
    authorizedKeysFiles = lib.mkBefore ["/var/lib/hermes-ssh/%u/authorized_keys"];
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

  environment.systemPackages = guestTools;
  environment.variables = {
    AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;
    # Explicit false overrides the upstream .managed marker without patching it.
    HERMES_MANAGED = "false";
  };

  services.hermes-agent = {
    enable = true;
    package = hermesPackage;
    user = "agent";
    group = "agent";
    createUser = false;
    addToSystemPackages = true;
    extraPackages = guestTools;
    extraPlugins = [
      newApiCodexPlugin
      weixinChannelPlugin
    ];
  };

  # Seed only a new instance. Rebuilds must preserve user toggles, including
  # an explicitly empty plugin list, instead of restoring the initial values.
  system.activationScripts.hermes-user-config = lib.stringAfter ["users"] ''
    if [ ! -e /var/lib/hermes/.hermes/config.yaml ]; then
      install -d -m 2770 -o agent -g agent /var/lib/hermes/.hermes
      install -m 0660 -o agent -g agent ${initialUserConfig} /var/lib/hermes/.hermes/config.yaml
    fi
  '';
  system.activationScripts.hermes-agent-setup.deps = ["hermes-user-config"];

  # Pin the deployment baseline through Hermes' native managed scope. MCP
  # definitions and personal credentials stay in the writable HERMES_HOME;
  # Nix must not reintroduce a server that its user has deleted.
  environment.etc = {
    "hermes/.env".source = "/run/hermes-secrets/.env";
    "hermes/config.yaml".text = builtins.toJSON {
      model = {
        provider = "codex-api";
        default = "gpt-6.1-sol";
        base_url = codexApiBaseUrl;
        api_mode = "codex_responses";
      };
      providers.codex-api = {
        api = codexApiBaseUrl;
        key_env = "NEWAPI_API_KEY";
        transport = "codex_responses";
      };
      providers.newapi = {
        api = newApiBaseUrl;
        key_env = "NEWAPI_API_KEY";
        transport = "codex_responses";
      };
      approvals.mode = "off";
      compression.threshold = 0.9;
      auxiliary.title_generation.model = "gpt-6-luna";
      memory.provider = "honcho";
      dashboard.public_url = dashboardPublicUrl;
      agent.system_prompt = ''
        Never run machine-learning model inference inside the Podman terminal environment. Use external APIs for inference.

        Prefer delegating programming tasks to the Codex CLI through the codex skill.

        Terminal commands run inside a Podman container isolated by gVisor's KVM platform. /workspace is persistent and shared with the Dashboard and Hermes Desktop. Save every file intended for the user to download under /workspace. /root is persistent for the terminal task but is not accessible to the Dashboard or Hermes Desktop. Other container filesystem changes may disappear when the container is replaced. The container does not run systemd, so manage processes directly rather than using systemctl.
      '';
      web.backend = "exa";
      telegram.extra.rich_messages = true;
      gateway.platforms.telegram.gateway_restart_notification = false;
      gateway.platforms.weixin.gateway_restart_notification = false;
      gateway.platforms.telegram.extra = lib.optionalAttrs telegramBotApi.enable {
        base_url = "${telegramBotApiBaseUrl}:${toString telegramBotApi.apiPort}/bot";
        base_file_url = "${telegramBotApiBaseUrl}:${toString telegramBotApi.filePort}/file/bot";
      };
      platform_toolsets.telegram = ["hermes-telegram"];
      image_gen.provider = "newapi-codex";
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
    unitConfig.RequiresMountsFor = "/run/hermes-secrets /var/lib/hermes";
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
      EnvironmentFile = "/run/hermes-secrets/.env";
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
    unitConfig.RequiresMountsFor = "/var/lib/hermes";
    environment = {
      HOME = "/var/lib/hermes";
      TMPDIR = podmanTmpDir;
      XDG_RUNTIME_DIR = podmanRuntimeDir;
    };
    path = [
      pkgs.coreutils
      config.virtualisation.podman.package
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "agent";
      Group = "agent";
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

      install -d -m 0700 "$state_dir"
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
    restartTriggers = [config.environment.etc."hermes/config.yaml".source];
    after = [
      "hermes-terminal-image.service"
      "lark-cli-init.service"
    ];
    requires = [
      "hermes-terminal-image.service"
      "lark-cli-init.service"
    ];
    unitConfig.RequiresMountsFor = "/run/hermes-secrets /var/lib/hermes";
    path = [config.virtualisation.podman.package];
    environment = {
      AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;
      HERMES_MANAGED = lib.mkForce "false";
      XDG_RUNTIME_DIR = podmanRuntimeDir;
    };
    serviceConfig = {
      Delegate = true;
      EnvironmentFile = "/run/hermes-secrets/.env";
      NoNewPrivileges = lib.mkForce false;
      ReadWritePaths = lib.mkAfter [podmanRuntimeDir];
    };
  };

  systemd.services.hermes-dashboard = {
    description = "Hermes Agent Dashboard";
    restartTriggers = [config.environment.etc."hermes/config.yaml".source];
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
    unitConfig.RequiresMountsFor = "/run/hermes-secrets /var/lib/hermes";
    environment = {
      AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;
      HERMES_HOME = "/var/lib/hermes/.hermes";
      HERMES_MANAGED = "false";
      HOME = "/var/lib/hermes";
      XDG_RUNTIME_DIR = podmanRuntimeDir;
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
      EnvironmentFile = "/run/hermes-secrets/.env";
      ExecStart = "${hermesPackage}/bin/hermes dashboard --host 0.0.0.0 --port 9119 --no-open";
      Restart = "always";
      RestartSec = 5;
      UMask = "0007";
      Delegate = true;
      NoNewPrivileges = false;
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = [
        "/var/lib/hermes"
        podmanRuntimeDir
      ];
      PrivateTmp = true;
    };
  };

  system.stateVersion = "26.05";
}
