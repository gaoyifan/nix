# Incus daemon for KVM virtual machines.
# Guests attach to the br0 bridge defined in networking.nix (no Incus-managed
# incusbr0 NAT bridge); AdGuard Home provides DHCP/DNS on that LAN.
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
              parent = "br0";
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
