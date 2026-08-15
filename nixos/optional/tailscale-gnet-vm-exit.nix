# Tailscale exit-node datapath for ordinary VMs with Ethernet WANs.
{...}: {
  imports = [./tailscale-gnet.nix];

  networking.nftables = {
    enable = true;
    tables.tailscale-exit-node-nat = {
      family = "inet";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          iifname "tailscale0" meta oiftype ether masquerade
        }
      '';
    };
  };
}
