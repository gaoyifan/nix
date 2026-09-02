{lib, ...}: {
  networking.edgeFirewall = {
    extraInputRules = lib.mkBefore [''iifname "podman*" meta l4proto { tcp, udp } th dport 53 accept''];
    extraForwardRules = [''iifname "podman*" accept''];
  };
}
