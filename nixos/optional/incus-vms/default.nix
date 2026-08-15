{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.virtualisation.incusVms;
  incus = "${config.virtualisation.incus.package}/bin/incus";

  nicHostName = vm: let
    mac = lib.replaceStrings [":"] [""] vm.macAddress;
  in "inc${builtins.substring 2 10 mac}";

  headlessQemuConfig = ''
    [object "mem0"]
    share = "off"
    merge = "on"

    [device "qemu_balloon"]
    free-page-reporting = "on"

    [machine]
    i8042 = "off"
    [device "qemu_gpu"]
    [device "qemu_keyboard"]
    [device "qemu_tablet"]
    [audiodev "qemu_sound-audiodev"]
    [device "qemu_sound"]
    [chardev "qemu_spice-chardev"]
    [device "qemu_spice"]
    [chardev "qemu_spicedir-chardev"]
    [device "qemu_spicedir"]
    [device "qemu_usb"]
    [chardev "qemu_spice-usb-chardev1"]
    [device "qemu_spice-usb1"]
    [chardev "qemu_spice-usb-chardev2"]
    [device "qemu_spice-usb2"]
    [chardev "qemu_spice-usb-chardev3"]
    [device "qemu_spice-usb3"]
  '';

  managedVms =
    lib.mapAttrs (name: vm: let
      profile = {
        name = "nixos-${name}";
        config =
          vm.config
          // {
            "boot.autostart" = "last-state";
          }
          // lib.optionalAttrs vm.headless {
            "raw.qemu.conf" = headlessQemuConfig;
          };
        devices =
          {
            eth0 = {
              type = "nic";
              name = "eth0";
              nictype = "bridged";
              parent = config.networking.homeRouter.switch.name;
              vlan = toString vm.vlan;
              hwaddr = vm.macAddress;
              host_name = nicHostName vm;
            };
            root =
              {
                type = "disk";
                path = "/";
                pool = vm.rootPool;
              }
              // lib.optionalAttrs (vm.rootSize != null) {size = vm.rootSize;}
              // vm.rootConfig;
          }
          // vm.extraDevices;
      };
    in {
      inherit (vm) image;
      inherit profile;
    })
    cfg.instances;
  vmSpec =
    lib.mapAttrs (_: vm: {
      inherit (vm) image;
      inherit (vm) profile;
    })
    managedVms;
  vmSpecFile = pkgs.writeText "incus-vms.json" (builtins.toJSON vmSpec);

  applyDeclarativeVms = pkgs.writeShellScriptBin "incus-apply-declarative-vms" ''
    export INCUS=${lib.escapeShellArg incus}
    export VM_SPEC=${vmSpecFile}
    exec ${pkgs.ruby}/bin/ruby ${./apply.rb} "$@"
  '';

  dropVmCaches = pkgs.writeShellScriptBin "incus-drop-vm-caches-on-low-memory" ''
    export INCUS=${lib.escapeShellArg incus}
    exec ${pkgs.ruby}/bin/ruby ${./drop-caches.rb}
  '';

  lanNamesForVlan = vlan:
    lib.filter (name: config.networking.homeRouter.lans.${name}.vlan == vlan) (lib.attrNames config.networking.homeRouter.lans);
  staticLeases = lib.concatMap (name: let
    vm = cfg.instances.${name};
  in
    lib.optional (vm.dhcpAddress != null) "${vm.macAddress},${vm.dhcpAddress},${name}")
  (lib.attrNames cfg.instances);
in {
  options.virtualisation.incusVms = {
    enable = lib.mkEnableOption "declarative Incus virtual machines";

    pools = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          driver = lib.mkOption {
            type = lib.types.str;
            default = "dir";
            description = "Incus storage pool driver.";
          };
          source = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional source passed to the Incus storage pool.";
          };
        };
      });
      default.default = {};
      description = "Declarative Incus storage pools keyed by pool name.";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          image = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Image used to create a missing VM; null requires an already imported instance.";
          };
          vlan = lib.mkOption {
            type = lib.types.ints.between 1 4094;
            description = "VLAN used by the managed access-port NIC.";
          };
          macAddress = lib.mkOption {
            type = lib.types.str;
            description = "Guest NIC MAC address.";
          };
          dhcpAddress = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional address reserved through homeRouter dnsmasq.";
          };
          config = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Incus instance configuration keys.";
          };
          rootSize = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Root disk size.";
          };
          rootPool = lib.mkOption {
            type = lib.types.str;
            default = "default";
            description = "Incus storage pool containing the VM root volume.";
          };
          rootConfig = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Additional properties applied to the root disk.";
          };
          extraDevices = lib.mkOption {
            type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
            default = {};
            description = "Additional Incus devices keyed by device name.";
          };
          headless = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to remove Incus desktop-oriented QEMU devices.";
          };
        };
      });
      default = {};
      description = "Declarative Incus VM inventory.";
    };

    metricsPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Loopback port exposing unauthenticated Incus metrics.";
    };
    cacheReclaim = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to ask running VM agents to drop caches under host memory pressure.";
    };
    requiredUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Units that must be active before Incus preseed and VM reconciliation.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.networking.homeRouter.enable;
          message = "virtualisation.incusVms requires networking.homeRouter.";
        }
        {
          assertion = lib.all (
            vm:
              vm.dhcpAddress
              == null
              || builtins.length (lanNamesForVlan vm.vlan) == 1
          ) (lib.attrValues cfg.instances);
          message = "An Incus VM with dhcpAddress must use exactly one declared homeRouter LAN VLAN.";
        }
        {
          assertion = lib.all (vm: !(vm.extraDevices ? eth0) && !(vm.extraDevices ? root)) (lib.attrValues cfg.instances);
          message = "Incus VM extraDevices may not replace the managed eth0 or root devices.";
        }
      ];

      virtualisation.incus = {
        enable = true;
        preseed = {
          config = lib.optionalAttrs (cfg.metricsPort != null) {
            "core.metrics_address" = "127.0.0.1:${toString cfg.metricsPort}";
            "core.metrics_authentication" = "false";
          };
          storage_pools =
            lib.mapAttrsToList (name: pool: {
              inherit name;
              inherit (pool) driver;
              config = lib.optionalAttrs (pool.source != null) {
                inherit (pool) source;
              };
            })
            cfg.pools;
          profiles =
            [
              {
                name = "default";
                devices = {
                  eth0 = {
                    type = "nic";
                    name = "eth0";
                    nictype = "bridged";
                    parent = config.networking.homeRouter.switch.name;
                  };
                  root = {
                    type = "disk";
                    path = "/";
                    pool = "default";
                  };
                };
              }
            ]
            ++ map (vm: vm.profile) (lib.attrValues managedVms);
        };
      };

      environment.systemPackages = [applyDeclarativeVms] ++ lib.optional cfg.cacheReclaim dropVmCaches;

      networking.homeRouter.internalDhcpHosts = lib.mkAfter staticLeases;

      systemd.services.incus-preseed = {
        after = cfg.requiredUnits;
        requires = cfg.requiredUnits;
      };

      systemd.services.incus-declarative-vms = {
        description = "Create and configure declarative Incus VMs";
        wants = ["incus.service" "network-online.target"];
        after = ["incus.service" "incus-preseed.service" "network-online.target"] ++ cfg.requiredUnits;
        requires = cfg.requiredUnits;
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "30min";
          Environment = ["HOME=/root"];
        };
        script = ''
          ${applyDeclarativeVms}/bin/incus-apply-declarative-vms --systemd
        '';
      };
    }

    (lib.mkIf cfg.cacheReclaim {
      systemd.services.incus-drop-vm-caches-on-low-memory = {
        description = "Drop Incus VM guest caches when host memory is low";
        wants = ["incus.service"];
        after = ["incus.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${dropVmCaches}/bin/incus-drop-vm-caches-on-low-memory";
        };
      };
      systemd.timers.incus-drop-vm-caches-on-low-memory = {
        description = "Check host memory pressure for Incus VM cache reclaim";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "1min";
          AccuracySec = "10s";
        };
      };
    })

    (lib.mkIf (cfg.metricsPort != null) {
      services.prometheus.scrapeConfigs = [
        {
          job_name = "incus";
          metrics_path = "/1.0/metrics";
          scheme = "https";
          static_configs = [{targets = ["127.0.0.1:${toString cfg.metricsPort}"];}];
          tls_config.insecure_skip_verify = true;
        }
      ];
      services.grafana.provision.dashboards.settings.providers = [
        {
          name = "incus-vm-performance";
          options.path = pkgs.writeTextDir "incus-vm-performance.json" (
            builtins.readFile ./performance.json
          );
        }
      ];
    })
  ]);
}
