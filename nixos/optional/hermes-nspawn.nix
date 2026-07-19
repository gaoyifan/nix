{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-nspawn;
  hostPkgs = pkgs;
  newApiBaseUrl = "http://somo-minisforum.ts.gaof.net:3000/v1";
  secretDirectory = containerName: "/run/${containerName}-secrets";
in {
  options.services.hermes-nspawn = {
    enable = lib.mkEnableOption "Hermes nspawn containers";
    containers = lib.mkOption {
      type = lib.types.attrs;
      description = "Hermes nspawn container definitions.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (containerName: container: {
        "${containerName}-secrets" = {
          description = "Prepare secrets for ${containerName}";
          before = ["container@${containerName}.service"];
          path = [
            pkgs.coreutils
            pkgs.openssl
          ];
          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
          };
          script = ''
            set -euo pipefail

            newapi_token="$(tr -d '\r\n' < ${container.newApiTokenFile})"
            exa_api_key="$(tr -d '\r\n' < /var/lib/hermes/exa_api_key)"
            lark_app_id="$(tr -d '\r\n' < /var/lib/hermes/lark_app_id)"
            lark_app_secret="$(tr -d '\r\n' < /var/lib/hermes/lark_app_secret)"

            if [[ -z "$newapi_token" ]]; then
              echo "${containerName}: New API token is empty" >&2
              exit 1
            fi
            if [[ -z "$exa_api_key" || -z "$lark_app_id" || -z "$lark_app_secret" ]]; then
              echo "${containerName}: Exa or Lark credentials are empty" >&2
              exit 1
            fi

            install -d -o root -g root -m 0700 /var/lib/hermes/dashboard
            if [[ ! -s /var/lib/hermes/dashboard/${containerName}.pass ]]; then
              openssl rand -base64 24 > /var/lib/hermes/dashboard/${containerName}.pass
              chmod 0600 /var/lib/hermes/dashboard/${containerName}.pass
            fi
            if [[ ! -s /var/lib/hermes/dashboard/${containerName}.secret ]]; then
              openssl rand -hex 32 > /var/lib/hermes/dashboard/${containerName}.secret
              chmod 0600 /var/lib/hermes/dashboard/${containerName}.secret
            fi

            dashboard_password="$(tr -d '\r\n' < /var/lib/hermes/dashboard/${containerName}.pass)"
            dashboard_secret="$(tr -d '\r\n' < /var/lib/hermes/dashboard/${containerName}.secret)"

            secrets_dir=${secretDirectory containerName}
            env_tmp="$secrets_dir/.env.tmp"
            install -d -o root -g 1000 -m 0750 "$secrets_dir"
            trap 'rm -f "$env_tmp"' EXIT

            install -o root -g 1000 -m 0640 /dev/null "$env_tmp"
            printf '%s\n' \
              'NEWAPI_BASE_URL=${newApiBaseUrl}' \
              "NEWAPI_API_KEY=$newapi_token" \
              "EXA_API_KEY=$exa_api_key" \
              'HERMES_DASHBOARD_BASIC_AUTH_USERNAME=agent' \
              "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$dashboard_password" \
              "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$dashboard_secret" \
              "LARK_APP_ID=$lark_app_id" \
              "LARK_APP_SECRET=$lark_app_secret" \
              > "$env_tmp"
            mv -f "$env_tmp" "$secrets_dir/.env"
          '';
        };
        "container@${containerName}" = {
          requires = ["${containerName}-secrets.service"];
          after = ["${containerName}-secrets.service"];
          restartTriggers = [container.newApiTokenFile];
        };
      })
      cfg.containers
    );

    containers =
      lib.mapAttrs (containerName: container: {
        autoStart = true;
        privateNetwork = true;
        hostBridge = container.bridge;
        localMacAddress = container.macAddress;
        timeoutStartSec = "15min";
        allowedDevices = [
          {
            node = "/dev/kvm";
            modifier = "rwm";
          }
        ];
        bindMounts = {
          "/dev/kvm" = {
            hostPath = "/dev/kvm";
            isReadOnly = false;
          };
          "/etc/hermes" = {
            hostPath = secretDirectory containerName;
            isReadOnly = true;
          };
        };
        config = {
          config,
          lib,
          pkgs,
          ...
        }: let
          inherit (import ../common/ssh-keys.nix) sshKeys;
          hermesPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.minimal.override {
            extraDependencyGroups = ["exa"];
          };
          tesseractWithLanguages = pkgs.tesseract.override {
            enableLanguages = [
              "eng"
              "chi_sim"
            ];
          };
          documentPython = pkgs.python3.withPackages (pythonPackages:
            with pythonPackages; [
              markitdown
              pdf2image
              pdfplumber
              pillow
              pypdf
              ((pytesseract.override {tesseract = tesseractWithLanguages;}).overridePythonAttrs {
                # Upstream tests require French and OSD data, which this
                # English/Chinese-only Tesseract intentionally omits.
                doCheck = false;
              })
              reportlab
            ]);
          newApiCodexPlugin = pkgs.runCommand "newapi-codex" {} ''
            mkdir -p $out
            cp -r ${./hermes-nspawn/newapi-codex}/. $out/
          '';
          managedSkills = pkgs.runCommand "hermes-managed-skills" {} ''
            mkdir -p $out
            cp -rL ${inputs.anthropic-skills}/skills/{docx,xlsx,pdf,pptx} $out/
            cp -rL ${inputs.lark-cli-src}/skills/lark-* $out/
            cp -rL ${./hermes-nspawn/skills/local-whisper-transcription} $out/local-whisper-transcription
          '';
          nixConfig = pkgs.writeTextDir "etc/nix/nix.conf" ''
            build-users-group =
            experimental-features = nix-command flakes
            extra-substituters = https://nix-cache.yfgao.net?priority=50
            extra-trusted-public-keys = nix-cache.yfgao.net-1:mSv/FykKK4oFZbX9JgD38D/me1+xJeAKsQ+STHiHVp4=
          '';
          codexCli = pkgs.writeShellScriptBin "codex" ''
            exec ${pkgs.nix}/bin/nix run \
              "github:gaoyifan/nix#codex" -- \
              --config 'model_provider="newapi"' \
              --config 'model_providers.newapi.name="New API"' \
              --config 'model_providers.newapi.base_url="${newApiBaseUrl}"' \
              --config 'model_providers.newapi.env_key="NEWAPI_API_KEY"' \
              "$@"
          '';
          guestTools = [
            pkgs.agent-browser
            pkgs.chromium
          ];
          terminalPackages = [
            pkgs.bashInteractive
            pkgs.bind.dnsutils
            pkgs.cacert
            codexCli
            pkgs.coreutils
            pkgs.curl
            pkgs.deno
            documentPython
            pkgs.ffmpeg
            pkgs.file
            pkgs.findutils
            pkgs.fontconfig
            pkgs.gawk
            pkgs.git
            pkgs.gnugrep
            pkgs.gnused
            pkgs.iproute2
            pkgs.iputils
            pkgs.jq
            pkgs.lark-cli
            pkgs.libreoffice
            pkgs.netcat-openbsd
            pkgs.nix
            pkgs.node-docx
            pkgs.nodejs_22
            pkgs.pandoc
            pkgs."poppler-utils"
            pkgs.procps
            pkgs.qpdf
            tesseractWithLanguages
            pkgs.util-linux
            pkgs.uv
            pkgs.yt-dlp
          ];
          aptProxy = pkgs.writeTextDir "etc/apt/apt.conf.d/01proxy" ''
            Acquire::http::Proxy "http://100.65.2.254:3142";
          '';
          ytDlpConfig = pkgs.writeTextDir "root/.config/yt-dlp/config" ''
            --remote-components ejs:npm
          '';
          fontConfig = pkgs.runCommand "hermes-fontconfig" {} ''
            mkdir -p $out/etc/fonts
            cp ${pkgs.makeFontsConf {fontDirectories = [pkgs.noto-fonts-cjk-sans];}} $out/etc/fonts/fonts.conf
          '';
          debianBase = pkgs.dockerTools.pullImage {
            imageName = "debian";
            imageDigest = "sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd";
            hash = "sha256-qSBIO82bf1xEUY3iQkhyrtvTUvt+QbJVTTGm5Bd4BKI=";
            finalImageName = "debian";
            finalImageTag = "trixie-slim";
          };
          terminalImageConfig = {
            Cmd = ["/bin/bash"];
            WorkingDir = "/workspace";
            Env = [
              "LANG=C.UTF-8"
              "LC_ALL=C.UTF-8"
              "FONTCONFIG_FILE=/etc/fonts/fonts.conf"
              "HERMES_HOME=/root/.hermes"
              "LARKSUITE_CLI_NO_SKILLS_NOTIFIER=1"
              "LARKSUITE_CLI_NO_UPDATE_NOTIFIER=1"
              "NODE_PATH=${pkgs.node-docx}/lib/node_modules"
              "PATH=${lib.makeBinPath terminalPackages}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
          terminalImageName = "localhost/hermes-terminal";
          terminalImage = pkgs.dockerTools.buildLayeredImageWithNixDb {
            name = terminalImageName;
            fromImage = debianBase;
            compressor = "zstd";
            contents = terminalPackages ++ [aptProxy fontConfig nixConfig ytDlpConfig];
            config = terminalImageConfig;
          };
          terminalImageRef = "${terminalImageName}:${terminalImage.imageTag}";
          dockerVolumes = [
            "${managedSkills}:${managedSkills}:ro"
            "/var/lib/hermes/.lark-cli:/root/.lark-cli:idmap=uids=1000-0-1;gids=1000-0-1"
            "/var/lib/hermes/.local/share/lark-cli:/root/.local/share/lark-cli:idmap=uids=1000-0-1;gids=1000-0-1"
          ];
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
                "wheel"
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
          security.sudo.wheelNeedsPassword = false;
          virtualisation = {
            podman.enable = true;
            containers.containersConf.settings = {
              engine = {
                runtime = "runsc";
                runtimes.runsc = ["${pkgs.gvisor}/bin/runsc"];
                runtimes_flags.runsc = ["platform=kvm"];
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
                max_tokens = 128000;
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
              compression.threshold = 0.95;
              auxiliary.title_generation.model = "gpt-5.6-luna";
              agent.system_prompt = ''
                Never run machine-learning model inference inside the Podman terminal environment. Use external APIs for inference.

                Prefer delegating programming tasks to the Codex CLI through the codex skill.

                Terminal commands run inside a Podman container isolated by gVisor's KVM platform. /workspace and /root are persistent for the task; other container filesystem changes may disappear when the container is replaced. The container does not run systemd, so manage processes directly rather than using systemctl.
              '';
              web.backend = "exa";
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
                docker_image = terminalImageRef;
                docker_volumes = dockerVolumes;
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

              image_ref=${lib.escapeShellArg terminalImageRef}
              state_dir=/var/lib/hermes/podman
              tag_file="$state_dir/terminal-image"

              find "$TMPDIR" -mindepth 1 -delete
              if ! podman image exists "$image_ref"; then
                podman load --input ${terminalImage}
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
            serviceConfig = {
              EnvironmentFile = "/etc/hermes/.env";
            };
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
        };
      })
      cfg.containers;
  };
}
