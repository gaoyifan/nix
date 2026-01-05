# Router module - imports all sub-modules
{...}: {
  imports = [
    ./options.nix
    ./core.nix
    ./interfaces.nix
    ./pppoe.nix
    ./wireguard.nix
    ./tailscale.nix
    ./policy-routing.nix
    ./nftables.nix
    ./adguard.nix
  ];
}
