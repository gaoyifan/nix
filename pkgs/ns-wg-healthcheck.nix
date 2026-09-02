{pkgs}:
pkgs.buildGoModule {
  pname = "ns-wg-healthcheck";
  version = "0-unstable-2026-05-19";
  # Vendored from gaoyifan/ns pdns branch at 25a32c4.
  src = ./ns-wg-healthcheck;
  vendorHash = "sha256-bnHJpCw4jsCKXEKh9vfPq7lftek8ktpmBghasfHrg0k=";
  meta.mainProgram = "ns-wg-healthcheck";
}
