{
  config,
  inputs,
  lib,
  ...
}: {
  config = lib.mkIf config.microvm.host.enable {
    microvm.vms.rakazo = {
      autostart = false;
      config = {
        imports = [((import ./guest-os.nix).guest inputs.rakazo-src)];

        microvm = {
          hypervisor = "cloud-hypervisor";
          vcpu = 4;
          mem = 6144;
          balloon = true;
          vsock.cid = 1001;
          interfaces = [
            {
              type = "tap";
              id = "rakazo-tap";
              mac = "02:52:00:00:00:01";
            }
          ];
          volumes = [
            {
              image = "/pool1/services/rakazo/var.img";
              mountPoint = "/var";
              size = 81920;
            }
          ];
          shares = [
            {
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              tag = "ro-store";
              proto = "virtiofs";
              readOnly = true;
            }
            {
              source = "/run/rakazo";
              mountPoint = "/etc/rakazo-secrets";
              tag = "secrets";
              proto = "virtiofs";
              readOnly = true;
            }
          ];
        };

        users.users.root.openssh.authorizedKeys.keys =
          if config.services.secrets.hasRealFiles
          then (import (config.services.secrets.filesDir + "/secrets.nix"))."nixos/el2/rakazo-env.age".publicKeys
          else lib.attrValues (import ../../../../common/ssh-keys.nix).userKeys;
      };
    };
  };
}
