# Incus daemon for KVM virtual machines.
# Guests attach by default to the br-somo bridge defined in networking.nix
# (no Incus-managed incusbr0 NAT bridge); dnsmasq provides DHCP/DNS there.
# Individual VMs may override eth0 to join br-gnet instead.
{username, ...}: {
  virtualisation.incus = {
    enable = true;
    preseed = {
      storage_pools = [
        {
          name = "default";
          driver = "dir";
        }
      ];
      profiles = [
        {
          name = "default";
          devices = {
            eth0 = {
              type = "nic";
              name = "eth0";
              nictype = "bridged";
              parent = "br-somo";
            };
            root = {
              type = "disk";
              path = "/";
              pool = "default";
            };
          };
        }
      ];
    };
  };

  # Manage Incus without sudo.
  users.users.${username}.extraGroups = ["incus-admin"];
}
