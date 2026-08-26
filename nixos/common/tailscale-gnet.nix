# Tailscale settings shared by all GNet nodes.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.tailscale;
  isExitNode = cfg.gnetMode == "exit-node";
  overlayRule = "lookup 52 suppress_prefixlength 0";
  gnetFlags = [
    "--accept-dns=false"
    "--accept-routes"
    "--netfilter-mode=off"
    "--operator=yifan"
    "--snat-subnet-routes=false"
  ];
in {
  imports = [../optional/policy-routing.nix];

  options.services.tailscale.gnetMode = lib.mkOption {
    type = lib.types.enum [
      "client"
      "exit-node"
    ];
    default = "exit-node";
    description = "GNet Tailscale operating mode.";
  };

  config = {
    age.secrets =
      lib.mkIf (
        config.services.secrets.hasRealFiles
        && cfg.authKeyFile == "/run/agenix/tailscale-auth-key"
      ) {
        tailscale-auth-key.file = config.services.secrets.filesDir + "/nixos/tailscale-auth-key.age";
      };

    networking.policyRouting = {
      ipv4.routingPolicyRules.postMain = lib.mkBefore [overlayRule];
      ipv6.routingPolicyRules.postMain = lib.mkBefore [overlayRule];
    };

    services.tailscale = {
      enable = true;
      authKeyFile = lib.mkDefault "/run/agenix/tailscale-auth-key";
      useRoutingFeatures =
        if isExitNode
        then "server"
        else "client";
      extraUpFlags =
        gnetFlags
        ++ (
          if isExitNode
          then ["--advertise-exit-node"]
          else ["--advertise-exit-node=false"]
        );
      extraSetFlags = cfg.extraUpFlags;
    };
  };
}
