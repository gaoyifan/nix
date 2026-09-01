{
  networking.edgeFirewall = {
    extraInputRules = [''iifname "podman*" meta l4proto { tcp, udp } th dport 53 accept''];
    extraForwardRules = [''iifname "podman*" accept''];
  };
}
