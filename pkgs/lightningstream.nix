{pkgs}: let
  version = "0.5.1";
in
  pkgs.lightningstream.overrideAttrs {
    inherit version;
    src = pkgs.fetchFromGitHub {
      owner = "PowerDNS";
      repo = "lightningstream";
      tag = "v${version}";
      hash = "sha256-fqitE52gM1h/MmAe+zyD/sGIUiXM/vwikqMKIqrKSQ0=";
    };
    vendorHash = "sha256-0sRuR+TyqsrL7euegpzFU2muniY28jDjVCDux8j116Q=";
    ldflags = [
      "-s"
      "-w"
      "-X main.version=${version}"
    ];
  }
