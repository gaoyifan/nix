# Nylon mesh node (overlay: 10.250.10.28 / fd10:250:10::28, node id "somo").
#
# Split responsibility with the server-maintenance Ansible repo:
#   * Nix (here): nylon binary, MPLS kernel setup, systemd service.
#   * Ansible (playbooks/nylon-deploy.yml): keypair plus /etc/nylon/central.yaml
#     and node.yaml, shared with the whole mesh. The service stays down until
#     those files exist.
{
  lib,
  pkgs,
  ...
}: {
  # mpls_iptunnel serves the wlt selector's `encap mpls` policy routes.
  boot.kernelModules = ["mpls_router" "mpls_iptunnel"];
  boot.kernel.sysctl."net.mpls.platform_labels" = 256;

  # `nylon` on PATH lets Ansible generate/verify keys and configs; python3 is
  # what Ansible modules run under on this host.
  environment.systemPackages = [
    pkgs.nylon
    pkgs.python3
  ];

  systemd.tmpfiles.rules = [
    "d /etc/nylon 0700 root root -"
    "d /var/log/nylon 0755 root root -"
  ];

  systemd.services.nylon = {
    description = "Nylon mesh router";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    # nylon shells out to `ip` for interface/route setup.
    path = [pkgs.iproute2];
    unitConfig.ConditionPathExists = [
      "/etc/nylon/central.yaml"
      "/etc/nylon/node.yaml"
    ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.nylon} run -c /etc/nylon/central.yaml -n /etc/nylon/node.yaml";
      WorkingDirectory = "/etc/nylon";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
