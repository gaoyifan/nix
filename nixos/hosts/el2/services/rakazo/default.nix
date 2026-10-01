{
  config,
  inputs,
  lib,
  ...
}: {
  imports = [
    (import ./guest-os.nix).host
    ./vm.nix
    inputs.microvm.nixosModules.host
  ];

  config = lib.mkIf config.microvm.host.enable {
    # Cloud Hypervisor's virtiofs shared-memory backend cannot use KSM.
    hardware.ksm.enable = false;
    age.secrets.rakazo-env = lib.mkIf config.services.secrets.hasRealFiles {
      file = config.services.secrets.filesDir + "/nixos/el2/rakazo-env.age";
    };
    networking.homeRouter = {
      internalDhcpHosts = ["02:52:00:00:00:01,100.64.2.81,rakazo"];
      switch.ports.rakazo-tap.untagged = 642;
    };
    services.tailscale.serve.services.rakazo = {
      advertised = true;
      certificate = {
        certFile = "${config.services.acmeCertificates.directory}/yfgao/fullchain.pem";
        keyFile = "${config.services.acmeCertificates.directory}/yfgao/privkey.pem";
      };
      tlsEndpoints."tcp:443" = "http://100.64.2.81:5173";
    };
  };
}
